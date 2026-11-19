defmodule Cinder.Filters.Autocomplete do
  @moduledoc """
  Autocomplete filter implementation for Cinder tables.

  Provides a searchable dropdown for cases where a standard select has too many
  options. Users type to filter the available options, with matching results
  shown in a dropdown.

  ## Options

  - `:options` - List of `{label, value}` tuples (required for static mode)
  - `:search` - A function from the typed term to `{label, value}` tuples (search mode)
  - `:lookup` - A function from a chosen value to its label, or `nil` (search mode)
  - `:placeholder` - Placeholder text for the search input
  - `:max_results` - Maximum number of results to show (default: 10)

  Search mode is for option lists too long to hold: the page renders only what
  `:search` returns, so it never has to load or send every option. The table calls
  `:search` and `:lookup` when the term or the chosen value changes, never while
  rendering.

  ## Examples

      # Static options
      <:col field={:category_id} label="Category"
        filter={[
          type: :autocomplete,
          options: [{"Electronics", 1}, {"Clothing", 2}, {"Books", 3}],
          max_results: 10,
          placeholder: "Search categories..."
        ]}
      />

      # Search mode
      <:col field={:customer_id} label="Customer"
        filter={[
          type: :autocomplete,
          search: &MyApp.Customers.search_options/1,
          lookup: &MyApp.Customers.option_label/1
        ]}
      />
  """

  @behaviour Cinder.Filter
  use Phoenix.Component
  use Cinder.Messages

  import Cinder.Filter, only: [get_option: 3, field_name: 1, filter_id: 2]
  alias Phoenix.LiveView.JS

  @default_max_results 10

  @impl true
  def render(column, current_value, theme, assigns) do
    filter_options = Map.get(column, :filter_options, [])
    all_options = get_option(filter_options, :options, [])

    default_placeholder = dgettext("cinder", "Search %{label}...", label: column.label)
    placeholder = get_option(filter_options, :placeholder, default_placeholder)
    max_results = get_option(filter_options, :max_results, @default_max_results)

    # Get search term from raw_filter_params (submitted via form)
    raw_filter_params = Map.get(assigns, :raw_filter_params, %{})
    search_key = "#{column.field}_autocomplete_search"
    search_term = Map.get(raw_filter_params, search_key, "")

    # Look up the display label for the current value
    current_label = find_label_for_value(all_options, current_value)

    {filtered_options, has_more} = matching_options(filter_options, search_term, max_results)

    # Sanitize field name for use in HTML attributes
    table_id = Map.get(assigns, :table_id)
    safe_field_name = Cinder.Filter.sanitized_field_name(column.field)

    # Use filter_id for consistent ID generation (or fallback for tests without table_id)
    {dropdown_id, input_id} =
      if table_id do
        base_id = filter_id(table_id, column.field)
        {"#{base_id}-dropdown", base_id}
      else
        {"autocomplete-dropdown-#{safe_field_name}", nil}
      end

    assigns = %{
      column: column,
      current_value: current_value || "",
      current_label: current_label,
      search_term: search_term,
      filtered_options: filtered_options,
      has_more: has_more,
      placeholder: placeholder,
      theme: theme,
      dropdown_id: dropdown_id,
      input_id: input_id,
      target: Map.get(assigns, :target)
    }

    ~H"""
    <div class={@theme.filter_select_container_class} data-key="filter_select_container_class" id={@dropdown_id}>
      <!-- Hidden input for the actual filter value -->
      <input
        type="hidden"
        name={field_name(@column.field)}
        value={@current_value}
      />

      <!-- Search input -->
      <input
        type="text"
        id={@input_id}
        name={"filters[#{@column.field}_autocomplete_search]"}
        value={if @current_value != "", do: @current_label, else: @search_term}
        placeholder={@placeholder}
        class={@theme.filter_text_input_class}
        data-key="filter_text_input_class"
        autocomplete="off"
        phx-debounce="300"
        phx-focus={JS.show(to: "##{@dropdown_id}-options")}
      />

      <!-- Dropdown options -->
      <div
        id={"#{@dropdown_id}-options"}
        class={[@theme.filter_select_dropdown_class, "hidden"]}
        data-key="filter_select_dropdown_class"
        phx-click-away={JS.hide(to: "##{@dropdown_id}-options")}
      >
        <label
          :for={{label, value} <- @filtered_options}
          class={[@theme.filter_select_option_class, "flex items-center cursor-pointer"]}
          data-key="filter_select_option_class"
        >
          <input
            type="radio"
            name={field_name(@column.field)}
            value={to_string(value)}
            checked={to_string(value) == to_string(@current_value)}
            class="sr-only"
            phx-click={JS.hide(to: "##{@dropdown_id}-options")}
          />
          <span class={@theme.filter_select_label_class} data-key="filter_select_label_class">
            {label}
          </span>
        </label>

        <div
          :if={@filtered_options == []}
          class={@theme.filter_select_empty_class}
          data-key="filter_select_empty_class"
        >
          {dgettext("cinder", "No results found")}
        </div>

        <div
          :if={@has_more}
          class={[@theme.filter_select_empty_class, "text-xs italic"]}
          data-key="filter_select_empty_class"
        >
          {dgettext("cinder", "Type to search more options...")}
        </div>
      </div>


    </div>
    """
  end

  @impl true
  def process(raw_value, column) when is_binary(raw_value) do
    trimmed = String.trim(raw_value)
    filter_options = Map.get(column, :filter_options, [])

    # A value from the client that isn't among the options can't be used: no filter
    if trimmed == "" or
         not Cinder.Filter.Helpers.client_value_allowed?(trimmed, filter_options) do
      nil
    else
      %{
        type: :autocomplete,
        value: trimmed,
        operator: :equals
      }
    end
  end

  def process(_raw_value, _column), do: nil

  @impl true
  def validate(value) do
    case value do
      %{type: :autocomplete, value: val, operator: :equals} when is_binary(val) ->
        val != ""

      _ ->
        false
    end
  end

  @impl true
  def default_options do
    [
      options: [],
      search: nil,
      lookup: nil,
      placeholder: nil,
      max_results: @default_max_results
    ]
  end

  @impl true
  def empty?(value) do
    case value do
      nil -> true
      "" -> true
      %{value: ""} -> true
      %{value: nil} -> true
      _ -> false
    end
  end

  @impl true
  def build_query(query, field, filter_value) do
    %{value: value} = filter_value

    # Use the centralized helper which supports direct, relationship, and embedded fields
    Cinder.Filter.Helpers.build_ash_filter(query, field, value, :equals)
  end

  @doc """
  The options to offer for `term`, at most `max_results` of them, and whether more match.
  A search-mode filter's options already are the search's answer, so they are not
  narrowed again by label.
  """
  def matching_options(filter_options, term, max_results) do
    options = get_option(filter_options, :options, [])

    matches =
      if search_mode?(filter_options) or term == "",
        do: options,
        else: Enum.filter(options, &label_matches?(&1, term))

    {Enum.take(matches, max_results), length(matches) > max_results}
  end

  defp label_matches?({label, _value}, term),
    do: String.contains?(String.downcase(to_string(label)), String.downcase(term))

  @doc false
  def search_mode?(filter_options), do: is_function(Keyword.get(filter_options, :search), 1)

  @doc """
  Runs the search of every search-mode autocomplete column whose term or chosen value
  changed since `previous`, and keeps the answer of the rest. Returns a map from field
  to `{{term, value}, options}`; `fill_searched_options/2` puts those options on columns.
  """
  def search_options(columns, filters, raw_filter_params, previous) do
    for %{filter_type: :autocomplete, filterable: true} = column <- columns,
        search_mode?(column.filter_options),
        into: %{} do
      term = Map.get(raw_filter_params, "#{column.field}_autocomplete_search", "")
      key = {term, chosen_value(filters, column.field)}

      case Map.get(previous, column.field) do
        {^key, _options} = kept -> {column.field, kept}
        _changed -> {column.field, {key, searched(column.filter_options, key)}}
      end
    end
  end

  defp chosen_value(filters, field) do
    case Map.get(filters, field) do
      %{value: value} when value not in [nil, ""] -> to_string(value)
      _none -> ""
    end
  end

  defp searched(filter_options, {term, value}) do
    found = Keyword.fetch!(filter_options, :search).(term)
    with_chosen(found, value, Keyword.get(filter_options, :lookup))
  end

  defp with_chosen(found, "", _lookup), do: found

  defp with_chosen(found, value, lookup) do
    if Enum.any?(found, fn {_label, v} -> to_string(v) == value end) do
      found
    else
      chosen_label(found, value, lookup)
    end
  end

  defp chosen_label(found, value, lookup) when is_function(lookup, 1) do
    case lookup.(value) do
      nil -> found
      text -> [{text, value} | found]
    end
  end

  defp chosen_label(found, _value, _lookup), do: found

  @doc """
  Puts the options `search_options/4` found on the search-mode columns they belong to.
  """
  def fill_searched_options(columns, searched) when map_size(searched) == 0, do: columns

  def fill_searched_options(columns, searched) do
    Enum.map(columns, fn column ->
      case Map.get(searched, column.field) do
        {_key, options} when column.filter_type == :autocomplete ->
          %{column | filter_options: Keyword.put(column.filter_options, :options, options)}

        _other ->
          column
      end
    end)
  end

  # Private helpers

  defp find_label_for_value(_options, nil), do: nil
  defp find_label_for_value(_options, ""), do: nil

  defp find_label_for_value(options, value) do
    value_string = to_string(value)

    case Enum.find(options, fn {_label, v} -> to_string(v) == value_string end) do
      {label, _value} -> label
      nil -> nil
    end
  end
end
