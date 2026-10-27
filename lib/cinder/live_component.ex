defmodule Cinder.LiveComponent do
  @moduledoc """
  Shared LiveComponent for all Cinder data layouts (Table, List, etc.).

  This component handles all data management logic:
  - State management (filters, sorting, pagination)
  - Event handling (filter_change, toggle_sort, goto_page, etc.)
  - Async data loading, with an optional synchronous first load
  - URL state synchronization

  The actual HTML rendering is delegated to a renderer module passed via
  the `renderer` assign. Each renderer implements a `render/1` function
  that receives the assigns and returns HEEx.
  """

  use Phoenix.LiveComponent
  require Logger
  use Cinder.Messages

  @impl true
  def mount(socket) do
    {:ok, socket}
  end

  @impl true
  def update(%{loading: true} = assigns, socket) do
    # Keep existing data visible while loading
    {:ok, assign(socket, Map.take(assigns, [:loading]))}
  end

  def update(%{refresh: true} = assigns, socket) do
    # Force refresh of data
    silent? =
      Map.get(assigns, :silent, false) == true and
        socket.assigns[:data] not in [nil, []]

    socket =
      socket
      |> assign(Map.drop(assigns, [:refresh, :silent]))
      |> assign_defaults()
      |> assign_column_definitions()
      |> load_data(silent?)

    {:ok, socket}
  end

  def update(%{__update_item__: {id, update_fn}}, socket) do
    id_field = socket.assigns[:id_field] || :id

    updated_data =
      Enum.map(socket.assigns.data || [], fn item ->
        if Map.get(item, id_field) == id, do: update_fn.(item), else: item
      end)

    {:ok, assign(socket, :data, updated_data)}
  end

  def update(%{__update_items__: {ids, update_fn}}, socket) do
    id_field = socket.assigns[:id_field] || :id
    id_set = MapSet.new(ids)

    updated_data =
      Enum.map(socket.assigns.data || [], fn item ->
        if Map.get(item, id_field) in id_set, do: update_fn.(item), else: item
      end)

    {:ok, assign(socket, :data, updated_data)}
  end

  def update(%{__remove_items__: ids}, socket) when is_list(ids) do
    id_field = socket.assigns[:id_field] || :id
    id_set = MapSet.new(ids, &to_string/1)
    data = socket.assigns.data || []

    updated_data =
      Enum.reject(data, fn item ->
        MapSet.member?(id_set, to_string(Map.get(item, id_field)))
      end)

    removed = length(data) - length(updated_data)
    selected_ids = socket.assigns[:selected_ids] || MapSet.new()
    updated_selected_ids = MapSet.difference(selected_ids, id_set)

    socket =
      socket
      |> assign(:data, updated_data)
      |> assign(:selected_ids, updated_selected_ids)
      |> assign(:page, drop_removed_from_page(socket.assigns[:page], updated_data, removed))
      |> update(:total_count, &(&1 && max(&1 - removed, 0)))

    socket =
      if MapSet.equal?(selected_ids, updated_selected_ids) do
        socket
      else
        notify_selection_change(socket, :remove)
      end

    socket =
      if updated_data == [] and data != [] do
        reload_emptied_page(socket)
      else
        socket
      end

    {:ok, socket}
  end

  # Single item update - raw item passed (has id field)
  def update(%{__update_item_if_visible__: {%{} = raw_item, update_fn}}, socket) do
    id_field = socket.assigns[:id_field] || :id
    id = Map.get(raw_item, id_field)
    do_update_item_if_visible(socket, id, raw_item, update_fn, id_field)
  end

  # Single item update - just ID passed
  def update(%{__update_item_if_visible__: {id, update_fn}}, socket) do
    id_field = socket.assigns[:id_field] || :id
    do_update_item_if_visible(socket, id, nil, update_fn, id_field)
  end

  # Single raw item passed (not in a list)
  def update(%{__update_items_if_visible__: {%{} = item, update_fn}}, socket) do
    id_field = socket.assigns[:id_field] || :id
    items_by_id = %{Map.get(item, id_field) => item}
    do_update_items_if_visible(socket, items_by_id, update_fn, id_field)
  end

  # List of raw items passed
  def update(%{__update_items_if_visible__: {[%{} | _] = items, update_fn}}, socket) do
    id_field = socket.assigns[:id_field] || :id
    items_by_id = Map.new(items, &{Map.get(&1, id_field), &1})
    do_update_items_if_visible(socket, items_by_id, update_fn, id_field)
  end

  # List of IDs passed (use old table data)
  def update(%{__update_items_if_visible__: {ids, update_fn}}, socket) when is_list(ids) do
    id_field = socket.assigns[:id_field] || :id
    do_update_items_if_visible(socket, nil, ids, update_fn, id_field)
  end

  def update(%{__force_hydrate__: true}, socket) do
    {:ok,
     socket
     |> force_hydrate_column_prefs()
     |> force_hydrate_filter_prefs()
     |> force_hydrate_table_state()}
  end

  def update(assigns, socket) do
    prev_state = data_state(socket.assigns)

    socket =
      socket
      |> assign(assigns)
      |> assign_defaults()
      # After the definitions: whether the filter row needs an editor — and so
      # whether it is waiting on stored preferences — is derived there.
      |> assign_column_definitions()
      |> maybe_schedule_force_hydrate()
      |> decode_url_state(assigns)
      |> seed_default_filters()
      |> load_data_if_needed(prev_state)
      |> clear_selection_if_scope_changed(prev_state)

    {:ok, socket}
  end

  @scope_keys [:query, :actor_id, :tenant_id, :scope_id]

  # A new base query, actor, tenant or scope means a different set of records, so a
  # selection made in the old one is cleared: otherwise it would count records the
  # bulk actions can no longer reach. The user's own filters, sort and page are left
  # alone, since a selection is meant to survive those.
  defp clear_selection_if_scope_changed(socket, prev_state) do
    scope_changed? =
      Map.take(data_state(socket.assigns), @scope_keys) != Map.take(prev_state, @scope_keys)

    if scope_changed? and MapSet.size(socket.assigns[:selected_ids] || MapSet.new()) > 0 do
      socket
      |> assign(:selected_ids, MapSet.new())
      |> notify_selection_change(:clear)
    else
      socket
    end
  end

  defp do_update_item_if_visible(socket, id, raw_item, update_fn, id_field) do
    data = socket.assigns.data || []

    case Enum.find(data, &(Map.get(&1, id_field) == id)) do
      nil ->
        {:ok, socket}

      old_item ->
        input = raw_item || old_item
        updated = update_fn.(input)
        updated_data = Enum.map(data, &if(Map.get(&1, id_field) == id, do: updated, else: &1))
        {:ok, assign(socket, :data, updated_data)}
    end
  end

  # When raw items provided as map
  defp do_update_items_if_visible(socket, items_by_id, update_fn, id_field) do
    do_update_items_if_visible(socket, items_by_id, Map.keys(items_by_id), update_fn, id_field)
  end

  defp do_update_items_if_visible(socket, items_by_id, ids, update_fn, id_field) do
    data = socket.assigns.data || []
    id_set = MapSet.new(ids)
    visible_ids = data |> Enum.map(&Map.get(&1, id_field)) |> MapSet.new()
    ids_to_update = MapSet.intersection(id_set, visible_ids)

    if MapSet.size(ids_to_update) == 0 do
      {:ok, socket}
    else
      input_items = get_input_items(data, items_by_id, ids_to_update, id_field)
      updated_by_id = update_fn.(input_items) |> to_map_by_id(id_field)

      updated_data =
        Enum.map(data, fn item ->
          id = Map.get(item, id_field)
          Map.get(updated_by_id, id, item)
        end)

      {:ok, assign(socket, :data, updated_data)}
    end
  end

  # Get input items from raw data if provided, otherwise from table data
  defp get_input_items(_data, items_by_id, ids_to_update, _id_field) when is_map(items_by_id) do
    ids_to_update |> Enum.map(&items_by_id[&1]) |> Enum.filter(& &1)
  end

  defp get_input_items(data, nil, ids_to_update, id_field) do
    Enum.filter(data, &(Map.get(&1, id_field) in ids_to_update))
  end

  # Normalize function return to map
  defp to_map_by_id(items, id_field) when is_list(items) do
    Map.new(items, &{Map.get(&1, id_field), &1})
  end

  defp to_map_by_id(items, _id_field) when is_map(items), do: items

  @impl true
  def render(assigns) do
    assigns =
      assign(
        assigns,
        :show_loading_state,
        assigns.loading and not Map.get(assigns, :silent, false)
      )

    # Delegate rendering to the renderer module
    assigns.renderer.render(assigns)
  end

  # ============================================================================
  # EVENT HANDLERS
  # ============================================================================

  @impl true
  def handle_event("goto_page", %{"page" => page}, socket) do
    with :offset <- socket.assigns.pagination_mode,
         {parsed, ""} when parsed > 0 <- Integer.parse(to_string(page)) do
      socket =
        socket
        |> assign(:current_page, parsed)
        |> notify_state_change()
        |> load_data()

      {:noreply, socket}
    else
      _ -> {:noreply, socket}
    end
  end

  # Keyset pagination: Navigate to next page
  @impl true
  def handle_event("next_page", _params, socket) do
    if socket.assigns.pagination_mode == :keyset do
      socket =
        socket
        |> assign(:after_keyset, socket.assigns.last_keyset)
        |> assign(:before_keyset, nil)
        |> notify_state_change()
        |> load_data()

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  # Keyset pagination: Navigate to previous page
  @impl true
  def handle_event("prev_page", _params, socket) do
    if socket.assigns.pagination_mode == :keyset do
      socket =
        socket
        |> assign(:before_keyset, socket.assigns.first_keyset)
        |> assign(:after_keyset, nil)
        |> notify_state_change()
        |> load_data()

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("change_page_size", %{"page_size" => page_size}, socket) do
    with {parsed, ""} <- Integer.parse(to_string(page_size)),
         validated when validated == parsed <-
           Cinder.PageSize.validate(parsed, socket.assigns.page_size_config) do
      updated_config = %{socket.assigns.page_size_config | selected_page_size: validated}

      socket =
        socket
        |> assign(:page_size, validated)
        |> assign(:page_size_config, updated_config)
        |> assign(:current_page, 1)
        # Clear keyset cursors to restart from beginning when page size changes
        |> assign(:after_keyset, nil)
        |> assign(:before_keyset, nil)
        |> notify_state_change()
        |> load_data()

      {:noreply, socket}
    else
      _ -> {:noreply, socket}
    end
  end

  @impl true
  def handle_event("clear_filter", %{"key" => "search"}, socket) do
    socket =
      socket
      |> assign(:search_term, "")
      |> assign(:current_page, 1)
      |> assign(:after_keyset, nil)
      |> assign(:before_keyset, nil)
      |> load_data()
      |> notify_state_change()

    {:noreply, socket}
  end

  @impl true
  def handle_event("clear_filter", %{"key" => key}, socket) do
    new_filters =
      socket.assigns.filters
      |> Cinder.FilterManager.clear_filter(key)
      |> Cinder.FilterManager.apply_defaults(socket.assigns.query_columns)

    # Also clear the autocomplete search term for this field
    old_raw_filter_params = Map.get(socket.assigns, :raw_filter_params, %{})
    autocomplete_search_key = "#{key}_autocomplete_search"
    raw_filter_params = Map.delete(old_raw_filter_params, autocomplete_search_key)

    # Clearing an input that holds only a partially entered value changes nothing here
    if new_filters == socket.assigns.filters and raw_filter_params == old_raw_filter_params do
      {:noreply, socket}
    else
      socket =
        socket
        |> assign(:filters, new_filters)
        |> assign(:raw_filter_params, raw_filter_params)
        |> assign(:current_page, 1)
        |> assign(:after_keyset, nil)
        |> assign(:before_keyset, nil)
        |> load_data()

      socket = notify_state_change(socket, new_filters)

      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("toggle_sort", %{"key" => key}, socket) do
    # The key is client-supplied. Anything that isn't a declared sortable column
    # is ignored: otherwise it reaches query validation, which would mint an atom
    # per distinct key (atom exhaustion) and let clients sort by hidden fields.
    case Enum.find(socket.assigns.columns, &(&1.field == key)) do
      %{sortable: true} = column -> {:noreply, toggle_sort(socket, column)}
      _ -> {:noreply, socket}
    end
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    {:noreply, load_data(socket)}
  end

  @impl true
  def handle_event("clear_all_filters", _params, socket) do
    new_filters =
      socket.assigns.filters
      |> Cinder.FilterManager.clear_all_filters()
      |> Cinder.FilterManager.apply_defaults(socket.assigns.query_columns)

    if new_filters == socket.assigns.filters and socket.assigns.search_term in [nil, ""] do
      {:noreply, socket}
    else
      # The search term goes with them. Search sits in the filter row and narrows
      # the list the same way a filter does, so a reset that left it applied would
      # hand back a list still missing rows with nothing on screen to say why —
      # the exact confusion the reset exists to undo.
      socket =
        socket
        |> assign(:filters, new_filters)
        |> assign(:search_term, "")
        |> assign(:current_page, 1)
        |> assign(:after_keyset, nil)
        |> assign(:before_keyset, nil)
        |> load_data()
        |> notify_state_change()

      {:noreply, socket}
    end
  end

  # ============================================================================
  # FILTER PREFERENCES EVENT HANDLERS
  # ============================================================================

  @impl true
  def handle_event("toggle_filter_visibility", %{"field" => field}, socket) do
    socket =
      update_filter_prefs(socket, fn prefs ->
        Cinder.FilterPreferences.toggle_hidden(prefs, field, socket.assigns.filter_prefs_columns)
      end)

    # A filter taken out of the row must not keep filtering from behind it.
    if Cinder.FilterPreferences.hidden?(socket.assigns.filter_preferences, field) do
      {:noreply, clear_field_filter(socket, field)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("reorder_filters", %{"order" => new_order}, socket)
      when is_list(new_order) do
    {:noreply,
     update_filter_prefs(socket, fn prefs ->
       Cinder.FilterPreferences.set_order(prefs, new_order, socket.assigns.filter_prefs_columns)
     end)}
  end

  @impl true
  def handle_event("reset_filter_preferences", _params, socket) do
    {:noreply,
     update_filter_prefs(socket, fn _prefs ->
       Cinder.FilterPreferences.from_columns(socket.assigns.filter_prefs_columns)
     end)}
  end

  @impl true
  def handle_event("apply_filter_preferences", payload, socket) do
    {:noreply, hydrate_filter_prefs(socket, payload)}
  end

  @impl true
  def handle_event("hydrate_table_state", payload, socket) do
    {:noreply, hydrate_table_state(socket, payload)}
  end

  @impl true
  def handle_event("toggle_filter_prefs_drawer", _params, socket) do
    {:noreply,
     assign(socket, :filter_prefs_drawer_open?, !socket.assigns[:filter_prefs_drawer_open?])}
  end

  # ============================================================================
  # COLUMN PREFERENCES EVENT HANDLERS
  # ============================================================================

  @impl true
  def handle_event("toggle_column_visibility", %{"field" => field}, socket) do
    socket =
      update_column_prefs(socket, fn prefs ->
        Cinder.ColumnPreferences.toggle_hidden(prefs, field, socket.assigns.declared_columns)
      end)

    # A hidden column must not keep filtering: clear its value. Its filter leaves
    # the row with it, because the controls are built from the visible columns.
    socket =
      if MapSet.member?(socket.assigns.column_preferences.hidden, field) do
        clear_field_filter(socket, field)
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("reorder_columns", %{"order" => new_order}, socket) when is_list(new_order) do
    {:noreply,
     update_column_prefs(socket, fn prefs ->
       Cinder.ColumnPreferences.set_order(prefs, new_order, socket.assigns.declared_columns)
     end)}
  end

  @impl true
  def handle_event("reset_column_preferences", _params, socket) do
    {:noreply,
     update_column_prefs(socket, fn _prefs ->
       Cinder.ColumnPreferences.from_columns(socket.assigns.declared_columns)
     end)}
  end

  @impl true
  def handle_event("apply_column_preferences", payload, socket) do
    {:noreply, hydrate_column_prefs(socket, payload)}
  end

  @impl true
  def handle_event("toggle_column_prefs_drawer", _params, socket) do
    {:noreply,
     assign(socket, :column_prefs_drawer_open?, !socket.assigns[:column_prefs_drawer_open?])}
  end

  # ============================================================================
  # SELECTION EVENT HANDLERS
  # ============================================================================

  @impl true
  def handle_event("toggle_select", %{"id" => id}, socket) do
    selected_ids = socket.assigns.selected_ids

    new_selected =
      cond do
        MapSet.member?(selected_ids, id) -> MapSet.delete(selected_ids, id)
        id_selectable?(socket, id) -> MapSet.put(selected_ids, id)
        true -> selected_ids
      end

    if MapSet.equal?(new_selected, selected_ids) do
      {:noreply, socket}
    else
      socket =
        socket
        |> assign(:selected_ids, new_selected)
        |> notify_selection_change(:toggle)

      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("toggle_select_all_page", _params, socket) do
    id_field = socket.assigns[:id_field] || :id
    selectable = socket.assigns[:selectable] || false

    page_ids =
      socket.assigns.data
      |> Enum.filter(&Cinder.Selection.item_selectable?(selectable, &1))
      |> Enum.map(&to_string(Map.get(&1, id_field)))
      |> MapSet.new()

    all_selected? =
      not Enum.empty?(page_ids) and MapSet.subset?(page_ids, socket.assigns.selected_ids)

    new_selected =
      if all_selected? do
        MapSet.difference(socket.assigns.selected_ids, page_ids)
      else
        MapSet.union(socket.assigns.selected_ids, page_ids)
      end

    socket =
      socket
      |> assign(:selected_ids, new_selected)
      |> notify_selection_change(:select_all)

    {:noreply, socket}
  end

  @impl true
  def handle_event("clear_selection", _params, socket) do
    socket =
      socket
      |> assign(:selected_ids, MapSet.new())
      |> notify_selection_change(:clear)

    {:noreply, socket}
  end

  # ============================================================================
  # BULK ACTION EVENT HANDLERS
  # ============================================================================

  @impl true
  # The index comes from the client, so it has to name one of the actions: a forged
  # one (a string, a negative index aliasing the last action) does nothing
  def handle_event("bulk_action_execute", %{"index" => index}, socket)
      when is_integer(index) and index >= 0 do
    slots = socket.assigns[:bulk_action_slots] || []
    slot = Enum.at(slots, index)

    if slot do
      execute_bulk_action(slot, socket)
    else
      Logger.warning("Cinder: Bulk action slot not found at index #{index}")
      {:noreply, socket}
    end
  end

  def handle_event("bulk_action_execute", params, socket) do
    Logger.warning("Cinder: Ignoring a bulk action with an invalid index: #{inspect(params)}")
    {:noreply, socket}
  end

  @impl true
  def handle_event("filter_change", params, socket) do
    query_columns = Map.get(socket.assigns, :query_columns, socket.assigns.columns)

    raw_filter_params = Map.get(params, "filters", %{})

    new_filters =
      raw_filter_params
      |> Cinder.FilterManager.params_to_filters(query_columns)
      |> Cinder.FilterManager.apply_defaults(query_columns)

    search_term =
      case Map.get(params, "search") do
        nil -> socket.assigns.search_term
        term -> term
      end

    url_sync_enabled = !!socket.assigns[:on_state_change]

    changed? = new_filters != socket.assigns.filters or search_term != socket.assigns.search_term

    socket =
      socket
      |> assign(:filters, new_filters)
      |> assign(:raw_filter_params, raw_filter_params)
      |> assign(:search_term, search_term)

    # A change that leaves the filters and search as they were, such as typing in an
    # autocomplete filter's search box, only redraws the filters: no reset, no reload.
    socket =
      if changed? do
        socket =
          socket
          |> assign(:current_page, 1)
          |> assign(:after_keyset, nil)
          |> assign(:before_keyset, nil)

        socket =
          if url_sync_enabled,
            do: assign(socket, :__reload_requested__, true),
            else: load_data(socket)

        notify_state_change(socket, new_filters)
      else
        socket
      end

    {:noreply, socket}
  end

  # ============================================================================
  # BULK ACTION HELPERS
  # ============================================================================

  defp toggle_sort(socket, column) do
    new_sort =
      Cinder.QueryBuilder.toggle_sort_with_cycle(
        socket.assigns.sort_by,
        column.field,
        column.sort_cycle,
        socket.assigns.sort_mode
      )

    # Check if URL sync is enabled
    url_sync_enabled = !!socket.assigns[:on_state_change]

    socket =
      socket
      |> assign(:sort_by, new_sort)
      |> assign(:current_page, 1)
      |> assign(:after_keyset, nil)
      |> assign(:before_keyset, nil)
      |> assign(:user_has_interacted, true)

    socket =
      if url_sync_enabled do
        assign(socket, :__reload_requested__, true)
      else
        load_data(socket)
      end

    notify_state_change(socket)
  end

  # Clears a single field's filter value (and its autocomplete search term) and
  # reloads. Shared by the `remove_filter` and hide-column flows so a hidden or
  # removed filter never keeps filtering invisibly. No-ops when the field has no
  # active filter (so it's safe on sockets without filter state).
  defp clear_field_filter(socket, field) do
    filters = Map.get(socket.assigns, :filters)

    if is_map(filters) and Map.has_key?(filters, field) do
      new_filters =
        filters
        |> Cinder.FilterManager.clear_filter(field)
        |> Cinder.FilterManager.apply_defaults(Map.get(socket.assigns, :query_columns, []))

      raw_filter_params =
        socket.assigns
        |> Map.get(:raw_filter_params, %{})
        |> Map.delete("#{field}_autocomplete_search")

      socket
      |> assign(:filters, new_filters)
      |> assign(:raw_filter_params, raw_filter_params)
      |> assign(:current_page, 1)
      |> assign(:after_keyset, nil)
      |> assign(:before_keyset, nil)
      |> load_data()
      |> notify_state_change(new_filters)
    else
      socket
    end
  end


  defp execute_bulk_action(slot, socket) do
    action = slot[:action]
    selected_ids = socket.assigns.selected_ids |> MapSet.to_list()

    if selected_ids == [] do
      {:noreply, socket}
    else
      resource = extract_resource(socket.assigns)

      if resource do
        # The base query, not just its resource: its filters, tenant and read action
        # bound what the action can touch, so a selected record that has since left
        # the collection's scope isn't acted on
        result =
          Cinder.BulkActionExecutor.execute(action,
            resource: socket.assigns.query,
            ids: selected_ids,
            id_field: socket.assigns[:id_field] || :id,
            actor: socket.assigns[:actor],
            tenant: socket.assigns[:tenant],
            scope: socket.assigns[:scope],
            action_opts: slot[:action_opts] || []
          )

        handle_bulk_action_result(result, slot, socket)
      else
        Logger.error("Cinder: No resource configured for bulk action")
        {:noreply, socket}
      end
    end
  end

  defp handle_bulk_action_result(result, slot, socket) do
    case result do
      {:ok, bulk_result} ->
        handle_bulk_action_success(slot, socket, bulk_result)

      {:error, reason} ->
        handle_bulk_action_error(slot, socket, reason)

      # Some records changed and some didn't: an error, but the data and selection
      # are stale either way (without `return_records?` there's no telling which ids
      # failed, and keeping them would re-apply the action to the ones that worked)
      {:partial_success, %Ash.BulkResult{errors: errors}} ->
        socket =
          socket
          |> assign(:selected_ids, MapSet.new())
          |> notify_selection_change(:clear)
          |> load_data()

        handle_bulk_action_error(slot, socket, errors || [], partial: true)
    end
  end

  defp handle_bulk_action_success(slot, socket, result) do
    selected_count = MapSet.size(socket.assigns.selected_ids)

    socket =
      socket
      |> assign(:selected_ids, MapSet.new())
      |> notify_selection_change(:clear)
      |> load_data()

    if event_name = slot[:on_success] do
      send(
        self(),
        {event_name,
         %{
           component_id: socket.assigns.id,
           action: slot[:action],
           count: selected_count,
           result: result
         }}
      )
    end

    {:noreply, socket}
  end

  defp handle_bulk_action_error(slot, socket, reason, opts \\ []) do
    partial? = Keyword.get(opts, :partial, false)

    Logger.error(
      "Cinder: Bulk action #{if partial?, do: "partly failed", else: "failed"}: #{inspect(reason)}"
    )

    if event_name = slot[:on_error] do
      send(
        self(),
        {event_name,
         %{
           component_id: socket.assigns.id,
           action: slot[:action],
           reason: reason,
           partial: partial?
         }}
      )
    end

    {:noreply, socket}
  end

  defp extract_resource(assigns) do
    case assigns[:query] do
      %Ash.Query{resource: resource} -> resource
      resource when is_atom(resource) and not is_nil(resource) -> resource
      _ -> nil
    end
  end

  # The footer reads page.results and page.count
  defp drop_removed_from_page(%{results: _} = page, updated_data, removed) do
    page = %{page | results: updated_data}

    case Map.get(page, :count) do
      count when is_integer(count) -> %{page | count: max(count - removed, 0)}
      _ -> page
    end
  end

  defp drop_removed_from_page(page, _updated_data, _removed), do: page

  # A removal that empties the page reads it again, so the following rows move up
  # instead of the empty state showing. If the emptied page was the last offset page,
  # step back to the one before it.
  defp reload_emptied_page(socket) do
    %{pagination_mode: mode, current_page: current_page, page_size: page_size} =
      socket.assigns

    remaining = socket.assigns[:total_count]

    if mode == :offset and current_page > 1 and is_integer(remaining) and
         remaining <= (current_page - 1) * page_size do
      socket
      |> assign(:current_page, current_page - 1)
      |> load_data()
      |> notify_state_change()
    else
      load_data(socket)
    end
  end

  # A column's slot (or a raw slot's inner_block) is a HEEx closure over the parent
  # LiveView's assigns. The query never reads it, and carrying it into the async load
  # copies those assigns into the task once per column (process copies do not keep
  # sharing), which reached gigabytes on a busy page.
  defp without_slots(columns) do
    Enum.map(columns, fn column ->
      column |> Map.delete(:inner_block) |> Map.replace(:slot, nil)
    end)
  end

  defp maybe_notify_query_change(socket, nil), do: socket

  # An async count isn't known when the page loads; a second notification carries
  # it once it arrives (see `apply_count_result/2`).
  defp maybe_notify_query_change(socket, query) do
    count = if socket.assigns.count_mode == :async, do: nil, else: socket.assigns.total_count
    notify_query_change(socket, query, count)
  end

  defp notify_query_change(socket, query, count) do
    if event_name = socket.assigns[:on_query_change] do
      send(self(), {event_name, %{query: query, count: count, id: socket.assigns.id}})
    end

    socket
  end

  # The count Ash already returned for the page that was just loaded, so parents
  # can render a total without counting the same filter a second time. nil when
  # the read did not produce one.
  defp page_count(%Ash.Page.Offset{count: count}), do: count
  defp page_count(%Ash.Page.Keyset{count: count}), do: count
  defp page_count(%{results: results}) when is_list(results), do: length(results)
  defp page_count(_page), do: nil

  # The checkbox is only disabled client-side for non-selectable rows, and the
  # client can send arbitrary ids — re-check against the served page data.
  defp id_selectable?(socket, id) do
    selectable = socket.assigns[:selectable] || false
    id_field = socket.assigns[:id_field] || :id

    case Enum.find(socket.assigns.data, &(to_string(Map.get(&1, id_field)) == id)) do
      nil -> false
      item -> Cinder.Selection.item_selectable?(selectable, item)
    end
  end

  defp update_column_prefs(socket, prefs_fn) do
    new_prefs = prefs_fn.(socket.assigns.column_preferences)

    socket
    |> assign(:column_preferences, new_prefs)
    |> assign_column_definitions()
    |> push_column_prefs_to_client(new_prefs)
    |> maybe_notify_columns_change(new_prefs)
  end

  defp push_column_prefs_to_client(socket, prefs) do
    payload = Cinder.ColumnPreferences.to_payload(prefs)
    push_event(socket, "cinder:column_prefs_changed", Map.put(payload, :id, socket.assigns.id))
  end

  defp update_filter_prefs(socket, prefs_fn) do
    new_prefs = prefs_fn.(socket.assigns.filter_preferences)

    socket
    |> assign(:filter_preferences, new_prefs)
    |> assign_column_definitions()
    |> push_filter_prefs_to_client(new_prefs)
  end

  defp push_filter_prefs_to_client(socket, prefs) do
    payload = Cinder.FilterPreferences.to_payload(prefs)
    push_event(socket, "cinder:filter_prefs_changed", Map.put(payload, :id, socket.assigns.id))
  end

  defp maybe_notify_columns_change(socket, prefs) do
    if event_name = socket.assigns[:on_columns_change] do
      payload = %{prefs: Cinder.ColumnPreferences.to_payload(prefs), id: socket.assigns.id}
      send(self(), {event_name, payload})
    end

    socket
  end

  defp notify_selection_change(socket, action) do
    if event_name = socket.assigns[:on_selection_change] do
      payload = %{
        component_id: socket.assigns.id,
        selected_ids: socket.assigns.selected_ids,
        selected_count: MapSet.size(socket.assigns.selected_ids),
        action: action
      }

      send(self(), {event_name, payload})
    end

    socket
  end

  # ============================================================================
  # ASYNC HANDLERS
  # ============================================================================

  def handle_async(:load_data, {:ok, {{:ok, page}, query}}, socket) do
    socket =
      {:ok, page}
      |> handle_result(socket)
      |> maybe_notify_query_change(query)
      |> maybe_start_async_count(query)

    {:noreply, socket}
  end

  @impl true
  def handle_async(:load_data, {:ok, {{:error, error}, _query}}, socket) do
    {:noreply, handle_result({:error, error}, socket)}
  end

  @impl true
  def handle_async(:load_data, {:exit, reason}, socket) do
    {:noreply, handle_result({:exit, reason}, socket)}
  end

  # A result from a superseded count never arrives here: LiveView drops it,
  # because each `start_async(:load_count, ...)` replaces the one before.
  @impl true
  def handle_async(:load_count, {:ok, result}, socket) do
    {:noreply, apply_count_result(socket, result)}
  end

  @impl true
  def handle_async(:load_count, {:exit, reason}, socket) do
    {:noreply, apply_count_result(socket, {{:error, reason}, nil})}
  end

  defp handle_result({:ok, page}, socket) do
    socket
    |> store_page_count(page)
    |> assign(:loading, false)
    |> assign(:silent, false)
    |> assign(:error, false)
    |> assign(:data, page.results)
    |> assign(:page, page)
    # Update keyset cursors for navigation (only read in keyset mode)
    |> update_keyset_cursors(page)
    |> clamp_page(page)
  end

  defp handle_result({:error, error}, socket) do
    Logger.error(
      "Cinder query failed for #{inspect(socket.assigns.query)}: #{inspect(error)}",
      %{
        resource: socket.assigns.query,
        filters: socket.assigns.filters,
        sort_by: socket.assigns.sort_by,
        current_page: socket.assigns.current_page,
        error: inspect(error)
      }
    )

    handle_load_error(socket)
  end

  defp handle_result({:exit, reason}, socket) do
    Logger.error(
      "Cinder query crashed for #{inspect(socket.assigns.query)}: #{inspect(reason)}",
      %{
        resource: socket.assigns.query,
        filters: socket.assigns.filters,
        sort_by: socket.assigns.sort_by,
        current_page: socket.assigns.current_page,
        reason: inspect(reason)
      }
    )

    handle_load_error(socket)
  end

  defp handle_load_error(socket) do
    if socket.assigns.silent do
      socket
      |> assign(:loading, false)
      |> assign(:silent, false)
      |> assign(:error, false)
    else
      socket
      |> assign(:loading, false)
      |> assign(:error, true)
      |> assign(:data, [])
      |> assign(:page, nil)
    end
  end

  # Not just `Ash.Page.Keyset`: keyset mode's first page can arrive as an
  # `Ash.Page.Offset` (Ash falls back to the app's `default_page_type` when there's
  # no cursor), and its records still carry keyset metadata.
  defp update_keyset_cursors(socket, %{results: results}) do
    # Extract keysets from first and last results for navigation
    first_keyset = get_keyset_from_result(List.first(results))
    last_keyset = get_keyset_from_result(List.last(results))

    socket
    |> assign(:first_keyset, first_keyset)
    |> assign(:last_keyset, last_keyset)
  end

  # A page past the end of the data is a dead end that explains nothing: an empty
  # table reading "Page 7 of 2", with the page itself — not a filter — as the
  # reason, and no empty-state message able to say so. It is reachable whenever a
  # page number outlives the rows it was counted against: a remembered page in a
  # tab someone else deleted rows from, a stale bookmark, a hand-edited `?page=`.
  #
  # Rather than describe the state, remove it — pull back to the last page that
  # has rows. The URL and the stored state are corrected too, or the next visit
  # restores the same out-of-range page and pays for the same wasted query again.
  defp clamp_page(socket, %Ash.Page.Offset{} = page) do
    with {:ok, last} <- last_page(page),
         true <- socket.assigns.current_page > last do
      socket
      |> assign(:current_page, last)
      |> persist_state(nil)
      |> request_corrected_url()
      |> load_data()
    else
      _ -> socket
    end
  end

  defp clamp_page(socket, _page), do: socket

  # `:unknown` when the action cannot count. `count: true` is always asked for,
  # but a resource may refuse it, and a nil count is no evidence of being past
  # the end — clamping on it would strand every table on page 1.
  defp last_page(%Ash.Page.Offset{count: count, limit: limit})
       when is_integer(count) and is_integer(limit) and limit > 0 do
    {:ok, max(ceil(count / limit), 1)}
  end

  defp last_page(_page), do: :unknown

  defp get_keyset_from_result(nil), do: nil

  defp get_keyset_from_result(result) do
    case result do
      %{__metadata__: %{keyset: keyset}} -> keyset
      _ -> nil
    end
  end

  defp maybe_put_cursor(state, _key, nil), do: state
  defp maybe_put_cursor(state, key, cursor), do: Map.put(state, key, cursor)

  # ============================================================================
  # PRIVATE FUNCTIONS - State Notification
  # ============================================================================

  defp notify_state_change(socket, filters \\ nil) do
    socket
    |> persist_state(filters)
    |> Cinder.UrlManager.notify_state_change(current_state(socket, filters))
  end

  defp current_state(socket, filters) do
    filters = filters || socket.assigns.filters
    page_size_config = socket.assigns.page_size_config

    state = %{
      filters: filters,
      current_page: socket.assigns.current_page,
      sort_by: socket.assigns.sort_by,
      page_size: page_size_config.selected_page_size,
      default_page_size: page_size_config.default_page_size,
      search_term: socket.assigns.search_term,
      filter_field_names: socket.assigns.filter_field_names
    }

    # For keyset pagination, include after/before cursors for URL persistence
    if socket.assigns.pagination_mode == :keyset do
      state
      |> maybe_put_cursor(:after, socket.assigns.after_keyset)
      |> maybe_put_cursor(:before, socket.assigns.before_keyset)
    else
      state
    end
  end

  defp encoded_state(socket, filters) do
    Cinder.UrlManager.encode_state(current_state(socket, filters))
  end

  # Writing the stores follows every state change rather than being a separate
  # event, so a reset is persisted the same way a filter is: the payload for a
  # cleared filter is simply empty, which overwrites what was there.
  #
  # Nothing is written before hydration, or the state the browser is still about
  # to send would be overwritten by the URL it was meant to supplement.
  defp persist_state(
         %{assigns: %{persist_state?: true, table_state_hydrated?: true}} = socket,
         filters
       ) do
    payload =
      socket
      |> encoded_state(filters)
      |> Cinder.StateStorage.split()
      |> Map.put("id", socket.assigns.id)

    Phoenix.LiveView.push_event(socket, "cinder:table_state_changed", payload)
  end

  defp persist_state(socket, _filters), do: socket

  # ============================================================================
  # PRIVATE FUNCTIONS - URL State Decoding
  # ============================================================================

  defp decode_url_state(socket, assigns) do
    if Map.has_key?(assigns, :url_raw_params) do
      raw_params = assigns.url_raw_params

      decoded_filters =
        Cinder.UrlManager.decode_filters(raw_params, socket.assigns.query_columns)

      decoded_sorts =
        Cinder.UrlManager.decode_sort(Map.get(raw_params, "sort"), socket.assigns.columns)

      decoded_state = %{
        filters: decoded_filters,
        current_page: Cinder.UrlManager.decode_page(Map.get(raw_params, "page")),
        sort_by: decoded_sorts,
        page_size: Cinder.UrlManager.decode_page_size(Map.get(raw_params, "page_size")),
        search_term: Map.get(raw_params, "search", ""),
        after: Cinder.UrlManager.decode_cursor(Map.get(raw_params, "after")),
        before: Cinder.UrlManager.decode_cursor(Map.get(raw_params, "before"))
      }

      final_sort_by =
        cond do
          decoded_state.sort_by != [] ->
            decoded_state.sort_by

          Map.get(socket.assigns, :user_has_interacted, false) ->
            []

          true ->
            socket.assigns.sort_by
        end

      updated_socket =
        if Map.has_key?(raw_params, "page_size") do
          validated_page_size =
            Cinder.PageSize.validate(decoded_state.page_size, socket.assigns.page_size_config)

          updated_page_size_config = %{
            socket.assigns.page_size_config
            | selected_page_size: validated_page_size
          }

          socket
          |> assign(:page_size, validated_page_size)
          |> assign(:page_size_config, updated_page_size_config)
        else
          socket
        end

      # Handle keyset cursors from URL (after/before params)
      updated_socket =
        if socket.assigns.pagination_mode == :keyset do
          updated_socket
          |> maybe_assign_cursor(:after_keyset, decoded_state.after)
          |> maybe_assign_cursor(:before_keyset, decoded_state.before)
        else
          updated_socket
        end

      updated_socket
      |> assign(:filters, decoded_state.filters)
      |> assign(:current_page, decoded_state.current_page)
      |> assign(:sort_by, final_sort_by)
      |> assign(:search_term, decoded_state.search_term)
    else
      socket
    end
  end

  defp seed_default_filters(socket) do
    filters =
      Cinder.FilterManager.apply_defaults(
        socket.assigns.filters,
        socket.assigns.query_columns
      )

    assign(socket, :filters, filters)
  end

  defp maybe_assign_cursor(socket, _key, nil), do: socket
  defp maybe_assign_cursor(socket, key, cursor), do: assign(socket, key, cursor)

  # ============================================================================
  # PRIVATE FUNCTIONS - Initialization
  # ============================================================================

  defp assign_defaults(socket) do
    assigns = socket.assigns

    # Use existing page_size_config if already parsed by Collection,
    # otherwise parse the global default
    page_size_config =
      assigns[:page_size_config] || Cinder.PageSize.parse(nil)

    selected_page_size =
      Map.get(socket.assigns, :page_size) || page_size_config.selected_page_size

    updated_page_size_config = %{page_size_config | selected_page_size: selected_page_size}

    # Determine pagination mode (default to :offset for backwards compatibility)
    pagination_mode = assigns[:pagination_mode] || :offset

    socket
    |> assign(:page_size, selected_page_size)
    |> assign(:page_size_config, updated_page_size_config)
    |> assign(:current_page, assigns[:current_page] || 1)
    |> assign(:loading, false)
    |> assign(:error, assigns[:error] || false)
    |> assign(:data, assigns[:data] || [])
    |> assign(:sort_by, assigns[:sort_by] || extract_initial_sorts(assigns))
    |> assign(:filters, assigns[:filters] || %{})
    |> assign(:search_term, assigns[:search_term] || "")
    |> assign(:theme, assigns[:theme] || Cinder.Theme.default())
    |> assign(:query_opts, assigns[:query_opts] || [])
    |> assign(:initial_load, Map.get(assigns, :initial_load, :async))
    |> assign_new(:action, fn -> nil end)
    |> assign_new(:page, fn -> nil end)
    |> assign(:user_has_interacted, Map.get(socket.assigns, :user_has_interacted, false))
    # Keyset pagination state
    |> assign(:pagination_mode, pagination_mode)
    |> assign(:count_mode, Map.get(assigns, :count_mode, true))
    |> assign_new(:total_count, fn -> nil end)
    |> assign_new(:count_failed?, fn -> false end)
    |> assign(:after_keyset, assigns[:after_keyset])
    |> assign(:before_keyset, assigns[:before_keyset])
    |> assign(:first_keyset, assigns[:first_keyset])
    |> assign(:last_keyset, assigns[:last_keyset])
    # Selection state
    |> assign(:selectable, assigns[:selectable] || false)
    |> assign(:select_on_row_click, Map.get(assigns, :select_on_row_click, true))
    |> assign_new(:selected_ids, fn -> MapSet.new() end)
    |> assign(:on_selection_change, assigns[:on_selection_change])
    |> assign(:on_query_change, assigns[:on_query_change])
    |> assign(:id_field, assigns[:id_field] || :id)
    |> assign(:sort_mode, assigns[:sort_mode] || :additive)
    |> assign_column_prefs_defaults(assigns)
    |> assign_state_storage_defaults(assigns)
    # Bulk actions
    |> assign_new(:bulk_action_slots, fn -> [] end)
  end

  # Remembering state is opt-in, like column preferences.
  #
  # `table_state_hydrated?` hides the table until the browser has said what it
  # stored, exactly as the two preference gates do — so the rows the reader
  # would otherwise watch being filtered away are never painted. It does *not*
  # hold the query back: a table whose rows depend on a hook answering is a
  # table that shows nothing wherever that hook does not run, which includes
  # every host that has not registered it and every LiveView test. The price is
  # one extra query on a visit that restores something, which buys the table
  # working without JS.
  defp assign_state_storage_defaults(socket, assigns) do
    persist? = Map.get(assigns, :persist_state?, false)

    socket
    |> assign(:persist_state?, persist?)
    |> assign_new(:table_state_hydrated?, fn -> not persist? end)
  end

  defp assign_column_prefs_defaults(socket, assigns) do
    prefs_on? = assigns[:column_preferences?] || false

    socket
    |> assign(:column_preferences?, prefs_on?)
    |> assign(:show_prefs, assigns[:show_prefs] || false)
    |> assign(:header_trigger, assigns[:header_trigger] != false)
    |> assign(:on_columns_change, assigns[:on_columns_change])
    |> assign_new(:column_preferences, fn ->
      Cinder.ColumnPreferences.from_columns(assigns[:col] || [])
    end)
    |> assign_new(:column_prefs_drawer_open?, fn -> false end)
    |> assign_new(:column_prefs_hydrated?, fn -> not prefs_on? end)
    |> assign_new(:prefs_hydrate_scheduled?, fn -> false end)
    |> assign_filter_prefs_defaults(assigns)
  end

  # Filter preferences need no opt-in: `assign_column_definitions/1` decides
  # whether the row earns an editor, so the only thing to seed here is the state
  # it edits — filters declared `filter_default_visible: false` start hidden.
  # `filter_prefs_hydrated?` starts false and is resolved there too: a row with
  # no editor has nothing to hydrate and is never gated.
  defp assign_filter_prefs_defaults(socket, assigns) do
    declared =
      Enum.filter(
        assigns[:query_columns] || assigns[:col] || [],
        &Map.get(&1, :filterable, false)
      )

    socket
    |> assign_new(:filter_preferences, fn -> Cinder.FilterPreferences.from_columns(declared) end)
    |> assign_new(:filter_prefs_drawer_open?, fn -> false end)
    |> assign_new(:filter_prefs_hydrated?, fn -> false end)
  end

  # The hook pushes whatever the two stores held, even when that is nothing —
  # that push is what opens the gate, so a browser with an empty store is not
  # left waiting on the failsafe timer.
  defp hydrate_table_state(socket, payload) do
    socket = assign(socket, :table_state_hydrated?, true)
    url_params = socket.assigns[:url_raw_params] || %{}

    case Cinder.StateStorage.restore(url_params, payload, socket.assigns.filter_field_names) do
      {:ok, restored} ->
        # The second query of the visit, and the reason restoring is not free.
        # Loaded here rather than left to the URL patch because the patch is a
        # round trip away; `data_state/1` covers everything restored, so when it
        # does arrive `load_data_if_needed/2` sees no change and queries nothing.
        socket
        |> decode_url_state(%{url_raw_params: Map.merge(url_params, restored)})
        |> load_data()
        |> request_corrected_url()

      # The data is already loaded from the URL, and nothing was restored to
      # change it — opening the gate is the whole job.
      :none ->
        socket
    end
  end

  # Neither restoring nor clamping is a navigation the reader performed, so the
  # URL either produces replaces the current history entry instead of adding one
  # — otherwise Back would land on the same page shorn of its filters, or on the
  # out-of-range page just corrected. The parent LiveView owns the URL, so it
  # does the patching; `Cinder.UrlSync` injects the handler.
  defp request_corrected_url(socket) do
    if socket.assigns[:on_state_change] do
      send(self(), {:cinder_restore_url, socket.assigns.id, encoded_state(socket, nil)})
    end

    socket
  end

  defp force_hydrate_table_state(%{assigns: %{table_state_hydrated?: false}} = socket),
    do: assign(socket, :table_state_hydrated?, true)

  defp force_hydrate_table_state(socket), do: socket

  defp hydrate_column_prefs(socket, payload) do
    prefs = Cinder.ColumnPreferences.from_payload(payload, socket.assigns.declared_columns)

    socket
    |> assign(:column_preferences, prefs)
    |> assign(:column_prefs_hydrated?, true)
    |> assign_column_definitions()
  end

  defp force_hydrate_column_prefs(
         %{assigns: %{column_preferences?: true, column_prefs_hydrated?: false}} = socket
       ) do
    socket
    |> assign(:column_prefs_hydrated?, true)
    |> assign_column_definitions()
  end

  defp force_hydrate_column_prefs(socket), do: socket

  defp hydrate_filter_prefs(socket, payload) do
    prefs = Cinder.FilterPreferences.from_payload(payload, socket.assigns.filter_prefs_columns)

    socket
    |> assign(:filter_preferences, prefs)
    |> assign(:filter_prefs_hydrated?, true)
    |> assign_column_definitions()
  end

  defp force_hydrate_filter_prefs(%{assigns: %{filter_prefs_hydrated?: false}} = socket) do
    socket
    |> assign(:filter_prefs_hydrated?, true)
    |> assign_column_definitions()
  end

  defp force_hydrate_filter_prefs(socket), do: socket

  # One timer covers both editors: whichever gate is still closed when it fires
  # opens, so a browser that never answers the hook cannot leave the row or the
  # table invisible.
  defp maybe_schedule_force_hydrate(%{assigns: %{prefs_hydrate_scheduled?: true}} = socket),
    do: socket

  defp maybe_schedule_force_hydrate(socket) do
    if prefs_hydration_pending?(socket) do
      schedule_force_hydrate_when_connected(socket)
    else
      socket
    end
  end

  defp prefs_hydration_pending?(%{assigns: assigns}) do
    (assigns[:column_preferences?] && not assigns[:column_prefs_hydrated?]) ||
      (assigns[:filter_editable?] && not assigns[:filter_prefs_hydrated?]) ||
      (assigns[:persist_state?] && not assigns[:table_state_hydrated?])
  end

  defp schedule_force_hydrate_when_connected(socket) do
    if Phoenix.LiveView.connected?(socket) do
      Phoenix.LiveView.send_update_after(
        __MODULE__,
        [id: socket.assigns.id, __force_hydrate__: true],
        1000
      )

      assign(socket, :prefs_hydrate_scheduled?, true)
    else
      socket
    end
  end

  defp assign_column_definitions(socket) do
    declared_columns = socket.assigns.col
    prefs_on? = socket.assigns[:column_preferences?] || false
    prefs = socket.assigns.column_preferences

    visible = visible_columns(declared_columns, prefs_on?, prefs)
    drawer = drawer_columns(declared_columns, visible, prefs_on?, prefs)
    query = query_columns(socket, declared_columns)

    socket
    |> assign(:declared_columns, declared_columns)
    |> assign(:columns, visible)
    |> assign(:prefs_drawer_columns, drawer)
    |> assign(:query_columns, query)
    |> assign_filter_definitions(filter_columns(visible, query, declared_columns))
    |> assign(:filter_field_names, filterable_field_names(query))
  end

  # Every table gets the same row; a row with something worth editing also gets
  # the editor. Row and drawer work from one ordered list, so dragging a filter
  # in the drawer moves it in the row — independently of the column order.
  defp assign_filter_definitions(socket, filter_cols) do
    editable? = Cinder.FilterPreferences.editable?(filter_cols)
    prefs = socket.assigns.filter_preferences

    ordered =
      if editable?, do: Cinder.FilterPreferences.order(filter_cols, prefs), else: filter_cols

    socket
    |> assign(:filter_editable?, editable?)
    |> assign(:filter_columns, ordered)
    |> assign(:filter_prefs_columns, filter_cols)
    |> assign(:filter_prefs_drawer_columns, ordered)
  end

  # Columns whose filters the controls should show: the visible display columns
  # (so hidden columns drop their filter and order follows column order) plus any
  # query-only filterable columns, which aren't display columns and therefore have
  # no visibility to honour.
  defp filter_columns(visible, query, declared) do
    visible_filterable = Enum.filter(visible, & &1.filterable)
    seen = MapSet.new(visible_filterable, & &1.field)
    declared_fields = MapSet.new(declared, & &1.field)

    query_only =
      Enum.filter(query, fn column ->
        column.filterable and not MapSet.member?(seen, column.field) and
          not MapSet.member?(declared_fields, column.field)
      end)

    visible_filterable ++ query_only
  end

  defp visible_columns(declared, false, _prefs), do: declared
  defp visible_columns(declared, true, prefs), do: Cinder.ColumnPreferences.apply(declared, prefs)

  defp drawer_columns(declared, _visible, false, _prefs), do: declared

  defp drawer_columns(declared, visible, true, prefs) do
    (visible ++ Enum.filter(declared, &MapSet.member?(prefs.hidden, &1.field)))
    |> Enum.reject(fn col ->
      is_nil(col.field) or Cinder.ColumnPreferences.display_hidden?(col)
    end)
    |> dedupe_by_field()
  end

  # Preferences key on field, so a field maps to one drawer entry. Display-hidden
  # filter-only columns are already removed above, so this only collapses the
  # rare case of two visible columns declared with the same field; keep the first.
  defp dedupe_by_field(columns) do
    columns
    |> Enum.map(& &1.field)
    |> Enum.uniq()
    |> Enum.map(fn field -> Enum.find(columns, &(&1.field == field)) end)
  end

  # Columns used for filtering and searching. Cinder.Collection populates this
  # to include filter-only slots whose fields aren't visible in the table;
  # falls back to declared_columns when no separate list was provided.
  defp query_columns(socket, declared_columns) do
    Map.get(socket.assigns, :query_columns) || declared_columns
  end

  # Field names of filterable columns. Consumed by Cinder.UrlManager to know
  # which keys to read out of URL params when restoring filter state.
  defp filterable_field_names(query_columns) do
    query_columns
    |> Enum.filter(& &1.filterable)
    |> Enum.map(& &1.field)
  end

  defp extract_initial_sorts(assigns) do
    query = assigns[:query]
    columns = assigns[:col] || []

    simple_columns =
      Enum.map(columns, fn col ->
        field_name =
          case col.field do
            field when is_atom(field) -> Atom.to_string(field)
            field when is_binary(field) -> field
            field -> inspect(field)
          end

        %{field: field_name}
      end)

    query_sorts =
      case query do
        nil -> []
        query -> Cinder.QueryBuilder.extract_query_sorts(query, simple_columns)
      end

    Cinder.QueryBuilder.default_sorts_from_cycles(columns, query_sorts)
  end

  # ============================================================================
  # PRIVATE FUNCTIONS - Data Loading
  # ============================================================================

  # Keys that affect data queries - changes to these trigger a reload.
  # Note: actor, tenant, and scope are normalized separately to avoid
  # false positives from Ecto struct metadata differences.
  @data_keys ~w(filters sort_by current_page page_size search_term query query_opts after_keyset before_keyset)a

  defp data_state(assigns) do
    base_state = Map.take(assigns, @data_keys)

    Map.merge(base_state, %{
      count_mode: Map.get(assigns, :count_mode, true),
      actor_id: normalize_auth(assigns[:actor]),
      tenant_id: normalize_auth(assigns[:tenant]),
      scope_id: normalize_scope(assigns[:scope])
    })
  end

  defp normalize_auth(nil), do: nil
  defp normalize_auth(value) when is_binary(value) or is_atom(value), do: value
  defp normalize_auth(%{id: id}), do: id
  defp normalize_auth(value), do: value

  # Normalize scope by extracting IDs from nested structs
  defp normalize_scope(nil), do: nil

  defp normalize_scope(%_{} = scope) do
    scope
    |> Map.from_struct()
    |> normalize_scope()
  end

  defp normalize_scope(scope) when is_map(scope) do
    scope
    |> Enum.map(fn
      {key, %{id: id}} -> {key, id}
      {key, value} when is_map(value) -> {key, normalize_scope(value)}
      {key, value} -> {key, value}
    end)
    |> Enum.sort()
  end

  defp normalize_scope(value), do: value

  defp load_data_if_needed(socket, prev) do
    first_load = socket.assigns[:page] == nil
    curr = data_state(socket.assigns)
    state_changed = curr != prev
    reload_requested = socket.assigns[:__reload_requested__] == true
    socket = assign(socket, :__reload_requested__, false)

    if first_load or state_changed or reload_requested do
      load_data(socket)
    else
      socket
    end
  end

  defp load_data(socket, silent \\ false) do
    # A `:sync` collection spends exactly one blocking query, on its first load,
    # so the data is in the server-rendered HTML. Everything after that — including
    # a retry, if that first query failed — goes back to the async path.
    sync_initial_load? =
      socket.assigns[:initial_load] == :sync and
        socket.assigns[:__initial_sync_done__] != true

    %{
      query: resource,
      query_opts: query_opts,
      actor: actor,
      tenant: tenant,
      page_size: page_size,
      current_page: current_page,
      sort_by: sort_by,
      filters: filters,
      columns: columns,
      search_term: search_term,
      pagination_mode: pagination_mode,
      count_mode: count_mode,
      after_keyset: after_keyset,
      before_keyset: before_keyset
    } = socket.assigns

    scope = Map.get(socket.assigns, :scope)

    resource_var = resource

    # Use query_columns for filtering and searching (includes filter-only slots)
    query_columns = Map.get(socket.assigns, :query_columns, columns)

    action = Map.get(socket.assigns, :action)

    options = [
      actor: actor,
      tenant: tenant,
      scope: scope,
      action: action,
      query_opts: query_opts,
      filters: filters,
      sort_by: sort_by,
      page_size: page_size,
      current_page: current_page,
      columns: without_slots(query_columns),
      sort_columns: without_slots(columns),
      search_term: search_term,
      search_fn: socket.assigns.search_fn,
      pagination_configured: socket.assigns.page_size_config.configurable || page_size != 25,
      # Keyset pagination options
      pagination_mode: pagination_mode,
      count_mode: count_mode,
      after_keyset: after_keyset,
      before_keyset: before_keyset
    ]

    socket
    |> assign(:loading, true)
    |> assign(:silent, silent)
    |> assign(:error, false)
    |> then(fn socket ->
      # Build the query once so we can both execute it and hand it to the
      # on_query_change callback (if one is configured). maybe_notify_query_change/2
      # decides whether to actually notify.
      if sync_initial_load? or Application.get_env(:ash, :disable_async?) do
        socket = assign(socket, :__initial_sync_done__, true)

        try do
          case Cinder.QueryBuilder.build_query(resource_var, options) do
            {:ok, prepared_query} ->
              prepared_query
              |> Cinder.QueryBuilder.execute(options)
              |> handle_result(socket)
              |> maybe_notify_query_change(prepared_query)
              |> maybe_start_async_count(prepared_query)

            {:error, _} = error ->
              handle_result(error, socket)
          end
        rescue
          e -> handle_result({:exit, e}, socket)
        end
      else
        start_async(socket, :load_data, fn ->
          case Cinder.QueryBuilder.build_query(resource_var, options) do
            {:ok, prepared_query} ->
              {Cinder.QueryBuilder.execute(prepared_query, options), prepared_query}

            {:error, _} = error ->
              {error, nil}
          end
        end)
      end
    end)
  end

  # With `count: true` the page read counts too; with `false` there is never a total.
  # An async count keeps the last total on screen until the new one arrives.
  defp store_page_count(%{assigns: %{count_mode: true}} = socket, page),
    do: assign(socket, :total_count, page_count(page))

  defp store_page_count(%{assigns: %{count_mode: false}} = socket, _page),
    do: assign(socket, :total_count, nil)

  defp store_page_count(socket, _page), do: socket

  # Counts the loaded query in the background. Every load recounts.
  defp maybe_start_async_count(%{assigns: %{count_mode: :async}} = socket, %Ash.Query{} = query) do
    options = count_query_options(socket)
    count = fn -> {Cinder.QueryBuilder.count(query, options), query} end

    if Application.get_env(:ash, :disable_async?) do
      apply_count_result(socket, count.())
    else
      start_async(socket, :load_count, count)
    end
  end

  defp maybe_start_async_count(socket, _query), do: socket

  defp apply_count_result(socket, {{:ok, count}, query}) do
    socket
    |> assign(total_count: count, count_failed?: false)
    |> notify_query_change(query, count)
  end

  defp apply_count_result(socket, {{:error, reason}, _query}) do
    Logger.warning("Cinder count query failed: #{inspect(reason)}")
    assign(socket, total_count: nil, count_failed?: true)
  end

  defp count_query_options(socket) do
    [
      actor: socket.assigns.actor,
      tenant: socket.assigns.tenant,
      scope: Map.get(socket.assigns, :scope),
      query_opts: socket.assigns.query_opts
    ]
  end
end
