defmodule Cinder.FilterPrefsRenderTest do
  @moduledoc """
  Render-level tests for the filter-prefs drawer UI.

  Hits two layers:
    * `Cinder.Renderers.FilterPrefs.render/1` directly — for the drawer content
      that depends on internal `open?` state.
    * `Cinder.Collection.collection/1` via `render_component` — for the editor
      appearing (or not) based on how many filters a table declares.
  """

  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest

  alias Cinder.{FilterPreferences, Theme}
  alias Cinder.Renderers.FilterPrefs

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
      attribute(:email, :string)
      attribute(:status, :string)
      attribute(:city, :string)
    end

    actions do
      defaults([:create, :read, :update, :destroy])
    end
  end

  defp filter_col(field), do: %{field: field, label: String.capitalize(field)}

  defp assigns(opts) do
    %{
      id: "users",
      myself: 1,
      theme: Theme.default(),
      enabled: Keyword.get(opts, :enabled, true),
      open?: Keyword.get(opts, :open?, false),
      drawer_filters: Keyword.get(opts, :drawer_filters, [filter_col("name")]),
      prefs: Keyword.get(opts, :prefs, FilterPreferences.empty())
    }
  end

  describe "FilterPrefs.render/1" do
    test "renders the hydration hook and the closed drawer" do
      html = render_component(&FilterPrefs.render/1, assigns([]))

      assert html =~ "users-filter-prefs-hook"
      assert html =~ ~s(phx-hook="CinderFilterPrefs")
      assert html =~ "Edit filters"
      assert html =~ ~s(phx-click="toggle_filter_prefs_drawer")

      assert html =~ "translate-x-full"
      refute html =~ "translate-x-0"
      assert html =~ ~s(aria-modal="false")
    end

    test "open drawer slides in and takes the modal role" do
      html = render_component(&FilterPrefs.render/1, assigns(open?: true))

      assert html =~ "translate-x-0"
      refute html =~ "translate-x-full"
      assert html =~ ~s(aria-modal="true")
    end

    test "renders nothing when the row is too short to be editable" do
      html = render_component(&FilterPrefs.render/1, assigns(enabled: false))

      refute html =~ "Edit filters"
      refute html =~ "users-filter-prefs-hook"
    end

    test "renders one draggable row per filter, checked unless hidden" do
      html =
        render_component(
          &FilterPrefs.render/1,
          assigns(
            open?: true,
            drawer_filters: [filter_col("name"), filter_col("status")],
            prefs: %{order: nil, hidden: MapSet.new(["status"])}
          )
        )

      assert html =~ "users-filter-prefs-list"
      assert html =~ ~s(phx-hook="CinderFilterSortable")

      [name_row] = Regex.run(~r/<li[^>]*data-field="name"[\s\S]*?<\/li>/, html)
      [status_row] = Regex.run(~r/<li[^>]*data-field="status"[\s\S]*?<\/li>/, html)

      assert Regex.match?(~r/<input[^>]*\schecked[\s>]/, name_row)
      refute Regex.match?(~r/<input[^>]*\schecked[\s>]/, status_row)

      # No filter is pinned, so every row drags and none is disabled.
      assert name_row =~ ~s(data-reorderable="true")
      assert status_row =~ ~s(data-reorderable="true")
      refute Regex.match?(~r/<input[^>]*\sdisabled[\s>]/, html)
    end
  end

  describe "Cinder.collection — public surface" do
    defp collection_html(fields) do
      assigns = %{
        resource: TestUser,
        actor: nil,
        id: "users-table",
        col:
          Enum.map(fields, fn field ->
            %{field: field, label: String.capitalize(field), filter: true, __slot__: :col}
          end)
      }

      render_component(&Cinder.Collection.collection/1, assigns)
    end

    test "four filters get the editor without any opt-in" do
      html = collection_html(["name", "email", "status", "city"])

      assert html =~ "users-table-filter-prefs-hook"
      assert html =~ ~s(phx-click="toggle_filter_prefs_drawer")
      assert html =~ ~s(data-key="filter_prefs_button_class")
    end

    test "the filter row is invisible until the stored preferences arrive" do
      html = collection_html(["name", "email", "status", "city"])

      assert html =~ ~r/data-key="controls_class"[^>]*invisible/ or
               html =~ ~r/invisible[^"]*"\s+data-key="controls_class"/
    end

    test "three filters render the row whole, with no editor" do
      html = collection_html(["name", "email", "status"])

      refute html =~ "filter-prefs-hook"
      refute html =~ ~s(phx-click="toggle_filter_prefs_drawer")

      # Nothing to hydrate, so the row is never gated.
      refute html =~ ~r/data-key="controls_class"[^>]*invisible/
      refute html =~ ~r/invisible[^"]*"\s+data-key="controls_class"/
    end
  end
end
