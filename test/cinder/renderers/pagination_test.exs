defmodule Cinder.Renderers.PaginationTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest

  alias Cinder.Renderers.Pagination

  defp build_theme do
    %{
      pagination_wrapper_class: "pagination-wrapper",
      pagination_container_class: "pagination-container",
      pagination_info_class: "pagination-info",
      pagination_count_class: "pagination-count",
      pagination_nav_class: "pagination-nav",
      pagination_button_class: "pagination-button",
      pagination_step_class: "pagination-step",
      pagination_current_class: "pagination-current",
      pagination_ellipsis_class: "pagination-ellipsis",
      page_size_container_class: "page-size-container",
      page_size_label_class: "page-size-label",
      page_size_dropdown_class: "page-size-dropdown",
      page_size_dropdown_container_class: "page-size-dropdown-container",
      page_size_option_class: "page-size-option",
      page_size_selected_class: "page-size-selected"
    }
  end

  defp base_assigns(id) do
    %{
      id: id,
      theme: build_theme(),
      page: %Ash.Page.Offset{
        results: [%{id: 1}, %{id: 2}],
        count: 100,
        offset: 0,
        limit: 10,
        more?: true
      },
      page_size_config: %{
        configurable: true,
        selected_page_size: 10,
        default_page_size: 10,
        page_size_options: [10, 25, 50]
      },
      myself: nil,
      show_pagination: true,
      pagination_mode: :offset
    }
  end

  defp offset_assigns(page_number, total_count, limit) do
    base_assigns("my-table")
    |> Map.put(:page, %Ash.Page.Offset{
      results: Enum.to_list(1..limit),
      count: total_count,
      offset: (page_number - 1) * limit,
      limit: limit,
      more?: true
    })
  end

  describe "offset page range" do
    test "shows every page when they all fit" do
      html = render_component(&Pagination.render/1, offset_assigns(1, 70, 10))

      for page <- 1..7, do: assert(html =~ ~s(phx-value-page="#{page}") or html =~ ">#{page}<")
      refute html =~ "pagination-ellipsis"
    end

    test "keeps the first and last page reachable, with an ellipsis for the gap" do
      html = render_component(&Pagination.render/1, offset_assigns(10, 500, 10))

      assert html =~ ~s(phx-value-page="1")
      assert html =~ ~s(phx-value-page="50")
      assert html =~ "pagination-ellipsis"
      # The window sits around the current page, not at the start
      assert html =~ ~s(phx-value-page="9")
      assert html =~ ~s(phx-value-page="11")
      refute html =~ ~s(phx-value-page="25")
    end

    test "marks the current page for assistive tech and does not link it" do
      html = render_component(&Pagination.render/1, offset_assigns(3, 500, 10))

      assert html =~ ~s(aria-current="page")
      refute html =~ ~s(phx-value-page="3")
    end

    test "disables rather than hides prev and next at the ends" do
      first = render_component(&Pagination.render/1, offset_assigns(1, 500, 10))
      assert first =~ "disabled"
      assert first =~ "Previous"
      assert first =~ "Next"
    end
  end

  describe "page size dropdown IDs" do
    test "dropdown ID is prefixed with table ID" do
      assigns = base_assigns("my-table")
      html = render_component(&Pagination.render/1, assigns)

      # The dropdown should have an ID prefixed with the table ID
      assert html =~ ~s(id="my-table-page-size-options")
    end

    test "different table IDs produce different dropdown IDs" do
      html1 = render_component(&Pagination.render/1, base_assigns("table-1"))
      html2 = render_component(&Pagination.render/1, base_assigns("table-2"))

      # Each table should have its own unique dropdown ID
      assert html1 =~ ~s(id="table-1-page-size-options")
      assert html2 =~ ~s(id="table-2-page-size-options")

      # They should NOT have the old hardcoded ID
      refute html1 =~ ~s(id="page-size-options")
      refute html2 =~ ~s(id="page-size-options")
    end

    test "JS toggle targets the correct prefixed ID" do
      assigns = base_assigns("users-table")
      html = render_component(&Pagination.render/1, assigns)

      # The toggle should target the prefixed ID
      assert html =~ ~s(#users-table-page-size-options)
    end
  end
end
