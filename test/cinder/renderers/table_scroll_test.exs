defmodule Cinder.Renderers.TableScrollTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest

  defmodule TestUser do
    use Ash.Resource,
      domain: nil,
      data_layer: Ash.DataLayer.Ets,
      validate_domain_inclusion?: false

    ets do
      private?(true)
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:name, :string)
    end

    actions do
      defaults([:read])
    end
  end

  defmodule StickyTheme do
    use Cinder.Theme

    set :table_scroll_class, "scroll-shell"
    set :table_scroll_rail_class, "scroll-rail"
    set :table_scroll_thumb_class, "scroll-thumb"
  end

  defp render_table(theme) do
    render_component(&Cinder.Collection.collection/1, %{
      resource: TestUser,
      actor: nil,
      id: "users-table",
      theme: theme,
      col: [%{field: "name", __slot__: :col}]
    })
  end

  test "a theme without a rail class keeps the native scrollbar and attaches no hook" do
    html = render_table("default")

    refute html =~ "CinderTableScroll"
    refute html =~ "data-scroll-rail"
    assert html =~ ~r/data-key="table_wrapper_class"[^>]*data-scroll-body/
  end

  test "a theme with a rail class wraps the table in the scroll hook, rail hidden until measured" do
    html = render_table(StickyTheme)

    assert html =~
             ~r/id="users-table-scroll"[^>]*class="scroll-shell"[^>]*phx-hook="CinderTableScroll"/

    assert html =~ ~r/<div data-scroll-rail hidden aria-hidden="true" class="scroll-rail"/
    assert html =~ ~r/<div data-scroll-thumb class="scroll-thumb"/
  end
end
