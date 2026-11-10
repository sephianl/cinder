defmodule Cinder.FilterBarTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest

  alias Cinder.FilterBar

  defp filter(field, type, value, opts \\ []) do
    %{
      field: field,
      label: Keyword.get(opts, :label, String.capitalize(field)),
      type: type,
      value: value,
      clearable?: Keyword.get(opts, :clearable?, value not in ["", [], %{from: "", to: ""}]),
      options: Keyword.get(opts, :options, []),
      name: "filters[#{field}]",
      id: "t-filter-#{field}"
    }
  end

  defp controls(filters, opts) do
    %{
      filters: Enum.map(filters, &{String.to_atom(&1.field), &1}),
      search: Keyword.get(opts, :search),
      active_filter_count: Enum.count(filters, &FilterBar.active?/1),
      target: nil,
      theme: Cinder.Theme.default(),
      table_id: "t",
      filters_label: "Filters",
      filter_mode: :bar,
      filter_values: Map.new(filters, &{&1.field, &1.value}),
      raw_filter_params: %{}
    }
  end

  defp render_bar(filters, opts \\ []),
    do: render_component(&FilterBar.render/1, controls: controls(filters, opts))

  @status_options [options: [{"Active", "active"}, {"Archived", "archived"}]]

  describe "up to three filters" do
    test "shows every pill and no menu" do
      html =
        render_bar([
          filter("status", :select, "", options: @status_options),
          filter("name", :text, "")
        ])

      assert html =~ ~s(id="t-filter-bar-pill-status")
      assert html =~ ~s(id="t-filter-bar-pill-name")
      refute html =~ "data-hidden"
      refute html =~ ~s(id="t-filter-bar-add")
    end
  end

  describe "more than three filters" do
    setup do
      filters = [
        filter("status", :select, "active", options: @status_options),
        filter("name", :text, ""),
        filter("email", :text, ""),
        filter("city", :text, "")
      ]

      %{html: render_bar(filters)}
    end

    test "hides the pills of unused filters until opened", %{html: html} do
      assert pill_tag(html, "name") =~ ~r/ data-hidden[ >]/
      refute pill_tag(html, "status") =~ ~r/ data-hidden[ >]/
    end

    test "lists only the unused filters in the menu", %{html: html} do
      [menu] = Regex.run(~r/data-bar-menu.*?<\/div>/s, html)
      items = ~r/role="menuitem".*?>\s*(\w+)\s*</s |> Regex.scan(menu) |> Enum.map(&List.last/1)

      assert items == ["Name", "Email", "City"]
      assert html =~ ~s(data-bar-submenu="t-filter-bar-dropdown-name")
    end
  end

  defp pill_tag(html, field) do
    [tag] = Regex.run(~r/<div id="t-filter-bar-pill-#{field}"[^>]*>/, html)
    tag
  end

  test "a filter not offered stays out of the bar until something sets it" do
    unit = fn value -> Map.put(filter("unit", :text, value), :offered?, false) end

    html = render_bar([filter("status", :select, "", options: @status_options), unit.("")])
    assert pill_tag(html, "unit") =~ ~r/ data-hidden[ >]/
    refute pill_tag(html, "status") =~ ~r/ data-hidden[ >]/

    html = render_bar([filter("status", :select, "", options: @status_options), unit.("su-1")])
    refute pill_tag(html, "unit") =~ ~r/ data-hidden[ >]/
  end

  test "a filter not offered is left out of the menu and the count" do
    filters = [
      filter("status", :select, "", options: @status_options),
      filter("name", :text, ""),
      filter("email", :text, ""),
      Map.put(filter("unit", :text, ""), :offered?, false)
    ]

    html = render_bar(filters)

    refute html =~ ~s(id="t-filter-bar-add")
    refute pill_tag(html, "email") =~ ~r/ data-hidden[ >]/
  end

  test "an active pill shows the option's label and a clear button" do
    html = render_bar([filter("status", :select, "archived", options: @status_options)])

    assert html =~ "Archived"
    assert html =~ ~s(phx-value-key="status")
  end

  test "a pill holding its default has no clear button" do
    html =
      render_bar([
        filter("status", :select, "active", options: @status_options, clearable?: false)
      ])

    refute html =~ ~s(phx-value-key="status")
  end

  test "a select's dropdown lists the prompt as a choice" do
    html =
      render_bar([
        filter("status", :select, "", options: @status_options ++ [prompt: "All statuses"])
      ])

    assert html =~ "All statuses"
    assert html =~ ~s(type="radio")
  end

  test "a multi-select summarises several values as a count" do
    html =
      render_bar([
        filter("status", :multi_select, ["active", "archived"], options: @status_options)
      ])

    assert html =~ "2 selected"
  end

  test "a date range shows shortcuts above its own inputs and its days as <time>" do
    html =
      render_bar([filter("created_at", :date_range, %{from: "2026-11-02", to: "2026-11-08"})])

    assert html =~ ~s(data-cinder-range="last_week")
    assert html =~ ~s(name="filters[created_at_from]")
    assert html =~ ~s(<time datetime="2026-11-02" data-precision="day_month">)
    assert html =~ ~s(<time datetime="2026-11-08" data-precision="day_month">)
  end

  test "a one-day range shows one day" do
    html =
      render_bar([filter("created_at", :date_range, %{from: "2026-11-09", to: "2026-11-09"})])

    assert length(Regex.scan(~r/<time /, html)) == 1
  end

  test "a single date offers only day shortcuts" do
    html = render_bar([filter("day", :date, "")])

    assert html =~ ~s(data-cinder-range="today")
    refute html =~ ~s(data-cinder-range="last_week")
  end

  test "an autocomplete lists its matches in the dropdown itself, under the search field" do
    options = [options: [{"BIN-001", "BIN-001"}, {"BIN-002", "BIN-002"}, {"RACK-9", "RACK-9"}]]
    bins = filter("bin", :autocomplete, "RACK-9", options: options)

    controls =
      [bins]
      |> controls([])
      |> Map.put(:raw_filter_params, %{"bin_autocomplete_search" => "bin"})

    html = render_component(&FilterBar.render/1, controls: controls)

    assert html =~ ~s(name="filters[bin_autocomplete_search]")
    assert html =~ ~s(type="radio" name="filters[bin]" value="BIN-001")
    assert html =~ ~s(type="radio" name="filters[bin]" value="BIN-002")
    refute html =~ ~s(type="radio" name="filters[bin]" value="RACK-9")
    assert html =~ ~s(type="hidden" name="filters[bin]" value="RACK-9")
  end

  describe "a long list of options" do
    @many for n <- 1..12, do: {"Option #{n}", "o#{n}"}

    test "gets a search field above it that stays out of the form, and keeps every option" do
      for type <- [:select, :multi_select] do
        html =
          render_bar([
            filter("pick", type, if(type == :select, do: "", else: []), options: [options: @many])
          ])

        assert html =~ "data-bar-option-search"
        assert html =~ ~s(form="cinder-filter-bar-option-search")
        refute html =~ ~r/data-bar-option-search[^>]*name=/
        assert length(Regex.scan(~r/ data-bar-option[ >]/, html)) >= 12
      end
    end

    test "a short one does not" do
      html = render_bar([filter("status", :select, "", options: @status_options)])

      refute html =~ "data-bar-option-search"
    end
  end

  test "a number range summarises an open end" do
    assert FilterBar.summary_text(filter("age", :number_range, %{min: "18", max: ""})) == "≥ 18"
    assert FilterBar.summary_text(filter("age", :number_range, %{min: "", max: "65"})) == "≤ 65"
    assert FilterBar.summary_text(filter("age", :number_range, %{min: 18, max: 65})) == "18 – 65"
  end

  test "renders the search pill" do
    search = %{
      value: "abc",
      name: "search",
      label: "Search",
      placeholder: "Search…",
      id: "t-filter-search"
    }

    html = render_bar([], search: search)

    assert html =~ ~s(name="search")
    assert html =~ ~s(phx-value-key="search")
  end
end
