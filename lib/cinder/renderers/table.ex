defmodule Cinder.Renderers.Table do
  @moduledoc """
  Renderer for table layout.

  This module contains the render function and helper components for
  displaying data in a traditional HTML table format.
  """

  use Phoenix.Component
  use Cinder.Messages

  import Cinder.Renderers.Helpers

  alias Cinder.Renderers.BulkActions
  alias Cinder.Renderers.ColumnPrefs
  alias Cinder.Renderers.Pagination
  alias Cinder.Renderers.SortIcon
  alias Cinder.Selection

  @doc """
  Renders the table layout.
  """
  def render(assigns) do
    ~H"""
    <div class={[@theme.container_class, "relative"]} data-key="container_class">
      <!-- Filter Controls (including search) -->
      <div :if={@show_filters} class={@theme.controls_class} data-key="controls_class">
        <Cinder.FilterManager.render_filter_controls
          table_id={@id}
          columns={Map.get(assigns, :query_columns, @columns)}
          filters={@filters}
          theme={@theme}
          target={@myself}
          filters_label={@filters_label}
          filter_mode={@show_filters}
          search_term={@search_term}
          show_search={@search_enabled}
          search_label={@search_label}
          search_placeholder={@search_placeholder}
          raw_filter_params={Map.get(assigns, :raw_filter_params, %{})}
          controls_slot={Map.get(assigns, :controls_slot, [])}
        />
      </div>

      <!-- Column preferences (Edit columns) -->
      <ColumnPrefs.render
        id={@id}
        myself={@myself}
        theme={@theme}
        enabled={Map.get(assigns, :column_preferences?, false)}
        show_button={Map.get(assigns, :show_prefs, false)}
        open?={Map.get(assigns, :column_prefs_drawer_open?, false)}
        drawer_columns={Map.get(assigns, :prefs_drawer_columns, Map.get(assigns, :declared_columns, @columns))}
        prefs={Map.get(assigns, :column_preferences, Cinder.ColumnPreferences.empty())}
      />

      <!-- Bulk Actions -->
      <BulkActions.render
        selectable={@selectable}
        selected_ids={@selected_ids}
        bulk_action_slots={@bulk_action_slots}
        theme={@theme}
        myself={@myself}
      />

      <!-- Main table -->
      <div class={[
             @theme.table_wrapper_class,
             prefs_hydration_class(assigns)
           ]} data-key="table_wrapper_class">
        <table class={@theme.table_class} data-key="table_class">
          <thead class={@theme.thead_class} data-key="thead_class">
            <tr class={@theme.header_row_class} data-key="header_row_class">
              <th :if={Selection.enabled?(@selectable)} class={[@theme.th_class, "w-10"]} data-key="th_class">
                <input
                  type="checkbox"
                  checked={all_page_selected?(@selected_ids, @data, @id_field, @selectable)}
                  phx-click="toggle_select_all_page"
                  phx-target={@myself}
                  class={@theme.selection_checkbox_class}
                  data-key="selection_checkbox_class"
                />
              </th>
              <th :for={column <- @columns} class={[@theme.th_class, column.class]} data-key="th_class">
                <.header_content
                  variant={header_variant(column, @columns, assigns)}
                  column={column}
                  theme={@theme}
                  myself={@myself}
                  loading={@show_loading_state}
                  sort_by={@sort_by}
                  drawer_open?={Map.get(assigns, :column_prefs_drawer_open?, false)}
                  trigger_slot={Map.get(assigns, :columns_trigger_slot, [])}
                />
              </th>
            </tr>
          </thead>
          <tbody class={[@theme.tbody_class, (@show_loading_state && @theme.loading_row_class || "")]} data-key="tbody_class">
            <tr :for={item <- @data} :if={not @error}
                class={selection_classes(@theme.row_class, Map.get(assigns, :item_class), @row_click, row_selection(@selectable, Map.get(assigns, :select_on_row_click, true)), @selected_ids, item, @id_field, Map.get(@theme, :selected_row_class))}
                data-item-id={to_string(Map.get(item, @id_field))}
                data-key="row_class"
                phx-click={selection_click_action(@row_click, row_selection(@selectable, Map.get(assigns, :select_on_row_click, true)), @selected_ids, item, @id_field, @myself)}>
              <td :if={Selection.enabled?(@selectable)} class={[@theme.td_class, "w-10"]} data-key="td_class">
                <input
                  type="checkbox"
                  disabled={not Selection.item_toggleable?(@selectable, @selected_ids, item, @id_field)}
                  checked={Selection.item_selected?(@selected_ids, item, @id_field)}
                  phx-click="toggle_select"
                  phx-value-id={to_string(Map.get(item, @id_field))}
                  phx-target={@myself}
                  class={@theme.selection_checkbox_class}
                  data-key="selection_checkbox_class"
                />
              </td>
              <td :for={column <- @columns} class={[@theme.td_class, column.class]} data-key="td_class">
                <%!-- A self-closing `<:col field="..." />` has no content: show the field's value --%>
                <%= if column.slot[:inner_block] do %>
                  {render_slot(column.slot, item)}
                <% else %>
                  {column.inner_block.(item)}
                <% end %>
              </td>
            </tr>
            <!-- Error State -->
            <tr :if={@error and not @loading}>
              <td colspan={column_count(@columns, @selectable)} class={@theme.empty_class} data-key="error_class">
                <%= if has_slot?(assigns, :error_slot) do %>
                  {render_slot(@error_slot)}
                <% else %>
                  <div class={@theme.error_container_class} data-key="error_container_class">
                    <span class={@theme.error_message_class} data-key="error_message_class">{@error_message}</span>
                  </div>
                <% end %>
              </td>
            </tr>
            <!-- Empty State (only when not loading and not error) -->
            <tr :if={@data == [] and not @loading and not @error}>
              <td colspan={column_count(@columns, @selectable)} class={@theme.empty_class} data-key="empty_class">
                <%= if has_slot?(assigns, :empty_slot) do %>
                  {render_slot(@empty_slot, empty_context(assigns))}
                <% else %>
                  {@empty_message}
                <% end %>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <!-- Loading indicator -->
      <div :if={@show_loading_state} class={@theme.loading_overlay_class} data-key="loading_overlay_class">
        <%= if has_slot?(assigns, :loading_slot) do %>
          {render_slot(@loading_slot)}
        <% else %>
          <div class={@theme.loading_container_class} data-key="loading_container_class">
            <svg class={@theme.loading_spinner_class} data-key="loading_spinner_class" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
              <circle class={@theme.loading_spinner_circle_class} data-key="loading_spinner_circle_class" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
              <path class={@theme.loading_spinner_path_class} data-key="loading_spinner_path_class" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
            </svg>
            {@loading_message}
          </div>
        <% end %>
      </div>

      <!-- Pagination -->
      <Pagination.render
        page={@page}
        page_size_config={@page_size_config}
        theme={@theme}
        myself={@myself}
        show_pagination={@show_pagination}
        pagination_mode={@pagination_mode}
        total_count={Map.get(assigns, :total_count)}
        id={@id}
      />
    </div>
    """
  end

  # ============================================================================
  # HEADER CELL
  # ============================================================================

  attr :variant, :atom, required: true
  attr :column, :map, required: true
  attr :theme, :map, required: true
  attr :myself, :any, required: true
  attr :loading, :boolean, required: true
  attr :sort_by, :any, required: true
  attr :drawer_open?, :boolean, default: false
  attr :trigger_slot, :list, default: []

  defp header_content(%{variant: :columns_trigger, trigger_slot: []} = assigns) do
    ~H"""
    <div class="flex justify-end">
      <button
        type="button"
        phx-click="toggle_column_prefs_drawer"
        phx-target={@myself}
        class={@theme.column_prefs_header_trigger_class}
        data-key="column_prefs_header_trigger_class"
        aria-haspopup="dialog"
      >
        <.columns_icon class={@theme.column_prefs_button_icon_class} />
      </button>
    </div>
    """
  end

  defp header_content(%{variant: :columns_trigger} = assigns) do
    ~H"""
    {render_slot(@trigger_slot, %{
      toggle: Phoenix.LiveView.JS.push("toggle_column_prefs_drawer", target: @myself),
      open?: @drawer_open?
    })}
    """
  end

  defp header_content(%{variant: :sortable} = assigns) do
    ~H"""
    <div
      class={["cursor-pointer select-none", (@loading && @theme.loading_row_class || "")]}
      phx-click="toggle_sort"
      phx-value-key={@column.field}
      phx-target={@myself}
    >
      {@column.label}
      <span class={@theme.sort_indicator_class} data-key="sort_indicator_class">
        <SortIcon.sort_icon
          sort_direction={Cinder.QueryBuilder.get_sort_direction(@sort_by, @column.field)}
          theme={@theme}
          loading={@loading}
        />
      </span>
    </div>
    """
  end

  defp header_content(%{variant: :plain} = assigns) do
    ~H"""
    <div>{@column.label}</div>
    """
  end

  # ============================================================================
  # HELPER FUNCTIONS
  # ============================================================================

  defp all_page_selected?(selected_ids, data, id_field, selectable) when is_list(data) do
    selectable_items = Enum.filter(data, &Selection.item_selectable?(selectable, &1))

    selectable_items != [] and
      Enum.all?(selectable_items, fn item ->
        Selection.item_selected?(selected_ids, item, id_field)
      end)
  end

  defp all_page_selected?(_selected_ids, _data, _id_field, _selectable), do: false

  defp prefs_hydration_class(%{column_preferences?: true, column_prefs_hydrated?: false}),
    do: "invisible"

  defp prefs_hydration_class(_assigns), do: ""

  defp header_variant(column, columns, assigns) do
    cond do
      prefs_trigger?(column, columns, assigns) -> :columns_trigger
      column.sortable -> :sortable
      true -> :plain
    end
  end

  defp prefs_trigger?(column, columns, assigns) do
    Map.get(assigns, :column_preferences?, false) and Map.get(assigns, :header_trigger, true) and
      is_nil(column.field) and column == List.last(columns)
  end

  defp column_count(columns, selectable) do
    base_count = length(columns)
    if Selection.enabled?(selectable), do: base_count + 1, else: base_count
  end
end
