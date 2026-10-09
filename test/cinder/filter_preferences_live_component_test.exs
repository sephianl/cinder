defmodule Cinder.FilterPreferencesLiveComponentTest do
  @moduledoc """
  Integration tests for filter-preferences events on the LiveComponent.
  """

  use ExUnit.Case, async: true

  alias Cinder.{FilterPreferences, LiveComponent}

  defp col(field, opts \\ []) do
    %{
      field: field,
      label: field,
      hideable: true,
      reorderable: true,
      default_visible: true,
      filterable: Keyword.get(opts, :filterable, true),
      sortable: false,
      class: ""
    }
  end

  defp make_socket(opts) do
    declared = Keyword.fetch!(opts, :columns)

    assigns = %{
      __changed__: %{},
      id: "test-table",
      col: declared,
      declared_columns: declared,
      columns: declared,
      column_preferences?: false,
      column_preferences: Cinder.ColumnPreferences.empty(),
      on_columns_change: nil,
      column_prefs_drawer_open?: false,
      column_prefs_hydrated?: true,
      filter_preferences: Keyword.get(opts, :filter_preferences, FilterPreferences.empty()),
      filter_prefs_drawer_open?: false,
      filter_prefs_hydrated?: Keyword.get(opts, :filter_prefs_hydrated?, false),
      query_columns: declared,
      filter_prefs_columns: Enum.filter(declared, & &1.filterable),
      filter_field_names: [],
      filters: Keyword.get(opts, :filters, %{})
    }

    %Phoenix.LiveView.Socket{assigns: assigns, root_pid: self()}
  end

  # Four filters, so the editor is on.
  defp four_filters, do: [col("a"), col("b"), col("c"), col("d")]

  # Any event that recomputes the column definitions re-derives whether the
  # editor is on; hydration is the one that always runs, so drive it through that.
  defp derive(socket) do
    {:noreply, socket} = LiveComponent.handle_event("apply_filter_preferences", %{}, socket)
    socket
  end

  describe "the editor switches itself on" do
    test "three filters leave the row as declared" do
      socket = derive(make_socket(columns: [col("a"), col("b"), col("c")]))

      refute socket.assigns.filter_selector?
    end

    test "four filters turn the editor on" do
      socket = derive(make_socket(columns: four_filters()))

      assert socket.assigns.filter_selector?
    end

    test "non-filterable columns don't count towards the threshold" do
      columns = [col("a"), col("b"), col("c"), col("d", filterable: false)]
      socket = derive(make_socket(columns: columns))

      refute socket.assigns.filter_selector?
    end
  end

  describe "toggle_filter_visibility" do
    test "hides a filter and shows it again" do
      socket = make_socket(columns: four_filters())

      {:noreply, socket} =
        LiveComponent.handle_event("toggle_filter_visibility", %{"field" => "b"}, socket)

      assert FilterPreferences.hidden?(socket.assigns.filter_preferences, "b")

      {:noreply, socket} =
        LiveComponent.handle_event("toggle_filter_visibility", %{"field" => "b"}, socket)

      refute FilterPreferences.hidden?(socket.assigns.filter_preferences, "b")
    end

    test "leaves the columns the table shows alone" do
      socket = make_socket(columns: four_filters())

      {:noreply, socket} =
        LiveComponent.handle_event("toggle_filter_visibility", %{"field" => "b"}, socket)

      assert Enum.map(socket.assigns.columns, & &1.field) == ["a", "b", "c", "d"]
      assert socket.assigns.column_preferences.hidden == MapSet.new()
    end
  end

  describe "reorder_filters" do
    test "reorders the row without touching the column order" do
      socket = make_socket(columns: four_filters())

      {:noreply, socket} =
        LiveComponent.handle_event("reorder_filters", %{"order" => ["d", "c", "b", "a"]}, socket)

      assert socket.assigns.filter_preferences.order == ["d", "c", "b", "a"]
      assert Enum.map(socket.assigns.filter_columns, & &1.field) == ["d", "c", "b", "a"]
      assert Enum.map(socket.assigns.columns, & &1.field) == ["a", "b", "c", "d"]
    end
  end

  describe "reset_filter_preferences" do
    test "restores every filter in declared order" do
      socket =
        make_socket(
          columns: four_filters(),
          filter_preferences: %{order: ["d", "a"], hidden: MapSet.new(["b"])}
        )

      {:noreply, socket} =
        LiveComponent.handle_event("reset_filter_preferences", %{}, socket)

      assert socket.assigns.filter_preferences == FilterPreferences.empty()
      assert Enum.map(socket.assigns.filter_columns, & &1.field) == ["a", "b", "c", "d"]
    end
  end

  describe "apply_filter_preferences (client hydration)" do
    test "applies the stored payload and opens the hydration gate" do
      socket = make_socket(columns: four_filters())

      {:noreply, socket} =
        LiveComponent.handle_event(
          "apply_filter_preferences",
          %{"order" => ["c", "b", "a", "d"], "hidden" => ["d"]},
          socket
        )

      assert socket.assigns.filter_prefs_hydrated?
      assert socket.assigns.filter_preferences.hidden == MapSet.new(["d"])
      assert Enum.map(socket.assigns.filter_columns, & &1.field) == ["c", "b", "a", "d"]
    end

    test "an empty payload still opens the gate" do
      socket = make_socket(columns: four_filters())

      {:noreply, socket} = LiveComponent.handle_event("apply_filter_preferences", %{}, socket)

      assert socket.assigns.filter_prefs_hydrated?
      assert socket.assigns.filter_preferences == FilterPreferences.empty()
    end
  end

  describe "force-hydrate fallback" do
    test "opens the gate when the browser never answered the hook" do
      socket = make_socket(columns: four_filters())
      refute socket.assigns.filter_prefs_hydrated?

      {:ok, socket} = LiveComponent.update(%{__force_hydrate__: true}, socket)

      assert socket.assigns.filter_prefs_hydrated?
      assert Enum.map(socket.assigns.filter_columns, & &1.field) == ["a", "b", "c", "d"]
    end

    test "is a no-op once hydrated" do
      socket = make_socket(columns: four_filters(), filter_prefs_hydrated?: true)

      {:ok, socket} = LiveComponent.update(%{__force_hydrate__: true}, socket)

      assert socket.assigns.filter_prefs_hydrated?
    end
  end

  describe "toggle_filter_prefs_drawer" do
    test "opens and closes" do
      socket = make_socket(columns: four_filters())

      {:noreply, socket} = LiveComponent.handle_event("toggle_filter_prefs_drawer", %{}, socket)
      assert socket.assigns.filter_prefs_drawer_open?

      {:noreply, socket} = LiveComponent.handle_event("toggle_filter_prefs_drawer", %{}, socket)
      refute socket.assigns.filter_prefs_drawer_open?
    end
  end
end
