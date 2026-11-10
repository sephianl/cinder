defmodule Cinder.FilterBarInlineTest do
  use ExUnit.Case, async: false
  import Phoenix.LiveViewTest

  defmodule Toggle do
    @behaviour Cinder.Filter
    use Phoenix.Component

    @impl true
    def render(column, _value, _theme, _assigns) do
      assigns = %{name: Cinder.Filter.field_name(column.field)}
      ~H|<input type="radio" name={@name} value="on" data-toggle />|
    end

    @impl true
    def inline?, do: true

    @impl true
    def process(_raw, _column), do: nil
    @impl true
    def validate(_value), do: true
    @impl true
    def default_options, do: []
    @impl true
    def empty?(_value), do: true
    @impl true
    def build_query(query, _field, _value), do: query
  end

  setup do
    previous = Application.get_env(:cinder, :filters)
    Application.put_env(:cinder, :filters, test_toggle: Toggle)
    on_exit(fn -> Application.put_env(:cinder, :filters, previous || []) end)
  end

  test "an inline filter sits in the bar beside its label: no pill, no dropdown, not in the menu" do
    filters =
      for {field, type} <- [{"flag", :test_toggle}, {"a", :text}, {"b", :text}, {"c", :text}] do
        %{
          field: field,
          label: String.upcase(field),
          type: type,
          value: "",
          clearable?: false,
          options: [],
          name: "filters[#{field}]",
          id: "t-filter-#{field}"
        }
      end

    controls = %{
      filters: Enum.map(filters, &{String.to_atom(&1.field), &1}),
      search: nil,
      active_filter_count: 0,
      target: nil,
      theme: Cinder.Theme.default(),
      table_id: "t",
      filters_label: "Filters",
      filter_mode: :bar,
      filter_values: %{},
      raw_filter_params: %{}
    }

    html = render_component(&Cinder.FilterBar.render/1, controls: controls)

    assert html =~ ~s(name="filters[flag]" value="on" data-toggle)
    refute html =~ "t-filter-bar-pill-flag"
    refute html =~ "t-filter-bar-dropdown-flag"
    refute html =~ ~s(id="t-filter-bar-add")
  end
end
