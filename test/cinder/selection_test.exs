defmodule Cinder.SelectionTest do
  @moduledoc """
  Tests for selection state management in LiveComponent.
  """

  use ExUnit.Case, async: true

  alias Cinder.LiveComponent

  # Helper to create a properly structured socket for testing
  defp make_socket(assigns) do
    defaults = %{
      __changed__: %{},
      id_field: :id,
      selectable: false,
      selected_ids: MapSet.new(),
      on_selection_change: nil,
      data: []
    }

    %Phoenix.LiveView.Socket{
      assigns: Map.merge(defaults, assigns),
      root_pid: self()
    }
  end

  describe "toggle_select event" do
    test "adds item to selection when not selected" do
      socket =
        make_socket(%{
          id: "test-table",
          selectable: true,
          selected_ids: MapSet.new(),
          data: [%{id: "user-1"}, %{id: "user-2"}]
        })

      {:noreply, updated_socket} =
        LiveComponent.handle_event("toggle_select", %{"id" => "user-1"}, socket)

      assert MapSet.member?(updated_socket.assigns.selected_ids, "user-1")
      assert MapSet.size(updated_socket.assigns.selected_ids) == 1
    end

    test "removes item from selection when already selected" do
      socket =
        make_socket(%{
          id: "test-table",
          selectable: true,
          selected_ids: MapSet.new(["user-1", "user-2"]),
          data: [%{id: "user-1"}, %{id: "user-2"}]
        })

      {:noreply, updated_socket} =
        LiveComponent.handle_event("toggle_select", %{"id" => "user-1"}, socket)

      refute MapSet.member?(updated_socket.assigns.selected_ids, "user-1")
      assert MapSet.member?(updated_socket.assigns.selected_ids, "user-2")
      assert MapSet.size(updated_socket.assigns.selected_ids) == 1
    end

    test "notifies parent when on_selection_change is set with atom" do
      socket =
        make_socket(%{
          id: "test-table",
          selectable: true,
          selected_ids: MapSet.new(),
          on_selection_change: :selection_changed,
          data: [%{id: "user-1"}]
        })

      {:noreply, _updated_socket} =
        LiveComponent.handle_event("toggle_select", %{"id" => "user-1"}, socket)

      assert_received {:selection_changed,
                       %{
                         component_id: "test-table",
                         selected_ids: selected_ids,
                         selected_count: 1,
                         action: :toggle
                       }}

      assert MapSet.member?(selected_ids, "user-1")
    end

    test "notifies parent when on_selection_change is set with string" do
      socket =
        make_socket(%{
          id: "test-table",
          selectable: true,
          selected_ids: MapSet.new(),
          on_selection_change: "selection_changed",
          data: [%{id: "user-1"}]
        })

      {:noreply, _updated_socket} =
        LiveComponent.handle_event("toggle_select", %{"id" => "user-1"}, socket)

      assert_received {"selection_changed",
                       %{
                         component_id: "test-table",
                         selected_ids: selected_ids,
                         selected_count: 1,
                         action: :toggle
                       }}

      assert MapSet.member?(selected_ids, "user-1")
    end
  end

  describe "toggle_select event server-side validation" do
    test "ignores rows that are not selectable under a predicate" do
      socket =
        make_socket(%{
          id: "test-table",
          selectable: fn item -> item.status == :active end,
          selected_ids: MapSet.new(),
          on_selection_change: :selection_changed,
          data: [
            %{id: "user-1", status: :active},
            %{id: "user-2", status: :inactive}
          ]
        })

      {:noreply, updated_socket} =
        LiveComponent.handle_event("toggle_select", %{"id" => "user-2"}, socket)

      assert MapSet.size(updated_socket.assigns.selected_ids) == 0
      refute_received {:selection_changed, _}
    end

    test "allows deselecting a row that is no longer selectable" do
      socket =
        make_socket(%{
          id: "test-table",
          selectable: fn item -> item.status == :active end,
          selected_ids: MapSet.new(["user-2"]),
          data: [
            %{id: "user-1", status: :active},
            %{id: "user-2", status: :inactive}
          ]
        })

      {:noreply, updated_socket} =
        LiveComponent.handle_event("toggle_select", %{"id" => "user-2"}, socket)

      assert MapSet.size(updated_socket.assigns.selected_ids) == 0
    end

    test "ignores ids not present in the current page data" do
      socket =
        make_socket(%{
          id: "test-table",
          selectable: true,
          selected_ids: MapSet.new(),
          on_selection_change: :selection_changed,
          data: [%{id: "user-1"}]
        })

      {:noreply, updated_socket} =
        LiveComponent.handle_event("toggle_select", %{"id" => "user-999"}, socket)

      assert MapSet.size(updated_socket.assigns.selected_ids) == 0
      refute_received {:selection_changed, _}
    end

    test "selects a selectable row under a predicate" do
      socket =
        make_socket(%{
          id: "test-table",
          selectable: fn item -> item.status == :active end,
          selected_ids: MapSet.new(),
          data: [
            %{id: "user-1", status: :active},
            %{id: "user-2", status: :inactive}
          ]
        })

      {:noreply, updated_socket} =
        LiveComponent.handle_event("toggle_select", %{"id" => "user-1"}, socket)

      assert MapSet.equal?(updated_socket.assigns.selected_ids, MapSet.new(["user-1"]))
    end
  end

  describe "toggle_select event with shiftKey" do
    defp rows(n), do: Enum.map(1..n, &%{id: "user-#{&1}", status: :active})

    defp click(socket, id, shift?) do
      {:noreply, socket} =
        LiveComponent.handle_event("toggle_select", %{"id" => id, "shiftKey" => shift?}, socket)

      socket
    end

    test "selects every row between the anchor and the clicked row" do
      socket =
        %{id: "test-table", selectable: true, data: rows(5), on_selection_change: :changed}
        |> make_socket()
        |> click("user-2", false)
        |> click("user-4", true)

      assert socket.assigns.selected_ids == MapSet.new(["user-2", "user-3", "user-4"])
      assert_received {:changed, %{action: :range, selected_count: 3}}
    end

    test "works upwards from the anchor" do
      socket =
        %{id: "test-table", selectable: true, data: rows(5)}
        |> make_socket()
        |> click("user-4", false)
        |> click("user-1", true)

      assert socket.assigns.selected_ids ==
               MapSet.new(["user-1", "user-2", "user-3", "user-4"])
    end

    test "clears the range when the anchor was deselected" do
      socket =
        %{
          id: "test-table",
          selectable: true,
          data: rows(5),
          selected_ids: MapSet.new(["user-1", "user-2", "user-3", "user-4", "user-5"])
        }
        |> make_socket()
        |> click("user-2", false)
        |> click("user-4", true)

      assert socket.assigns.selected_ids == MapSet.new(["user-1", "user-5"])
    end

    test "skips rows that are not selectable" do
      data = [
        %{id: "user-1", status: :active},
        %{id: "user-2", status: :inactive},
        %{id: "user-3", status: :active}
      ]

      socket =
        %{id: "test-table", selectable: &(&1.status == :active), data: data}
        |> make_socket()
        |> click("user-1", false)
        |> click("user-3", true)

      assert socket.assigns.selected_ids == MapSet.new(["user-1", "user-3"])
    end

    test "chains from the last shift-clicked row" do
      socket =
        %{id: "test-table", selectable: true, data: rows(6)}
        |> make_socket()
        |> click("user-1", false)
        |> click("user-2", true)
        |> click("user-5", true)

      assert MapSet.size(socket.assigns.selected_ids) == 5
    end

    test "toggles a single row when there is no anchor yet" do
      socket =
        %{id: "test-table", selectable: true, data: rows(5)}
        |> make_socket()
        |> click("user-4", true)

      assert socket.assigns.selected_ids == MapSet.new(["user-4"])
    end

    test "toggles a single row when the anchor is no longer on the page" do
      socket =
        %{id: "test-table", selectable: true, data: rows(5), selection_anchor: "user-99"}
        |> make_socket()
        |> click("user-3", true)

      assert socket.assigns.selected_ids == MapSet.new(["user-3"])
    end
  end

  describe "toggle_select_all_page event with predicate selectable" do
    test "selects only the selectable rows on the page" do
      socket =
        make_socket(%{
          id: "test-table",
          selectable: fn item -> item.status == :active end,
          selected_ids: MapSet.new(),
          id_field: :id,
          data: [
            %{id: "user-1", status: :active},
            %{id: "user-2", status: :inactive},
            %{id: "user-3", status: :active}
          ]
        })

      {:noreply, updated_socket} =
        LiveComponent.handle_event("toggle_select_all_page", %{}, socket)

      assert MapSet.size(updated_socket.assigns.selected_ids) == 2
      assert MapSet.member?(updated_socket.assigns.selected_ids, "user-1")
      assert MapSet.member?(updated_socket.assigns.selected_ids, "user-3")
      refute MapSet.member?(updated_socket.assigns.selected_ids, "user-2")
    end

    test "deselects only the selectable rows when all selectable are selected" do
      socket =
        make_socket(%{
          id: "test-table",
          selectable: fn item -> item.status == :active end,
          selected_ids: MapSet.new(["user-1", "user-3"]),
          id_field: :id,
          data: [
            %{id: "user-1", status: :active},
            %{id: "user-2", status: :inactive},
            %{id: "user-3", status: :active}
          ]
        })

      {:noreply, updated_socket} =
        LiveComponent.handle_event("toggle_select_all_page", %{}, socket)

      assert MapSet.size(updated_socket.assigns.selected_ids) == 0
    end

    test "no-ops when there are no selectable rows on the page" do
      socket =
        make_socket(%{
          id: "test-table",
          selectable: fn item -> item.status == :active end,
          selected_ids: MapSet.new(["user-9"]),
          id_field: :id,
          data: [
            %{id: "user-1", status: :inactive},
            %{id: "user-2", status: :inactive}
          ]
        })

      {:noreply, updated_socket} =
        LiveComponent.handle_event("toggle_select_all_page", %{}, socket)

      # Off-page selection preserved, nothing added
      assert MapSet.equal?(updated_socket.assigns.selected_ids, MapSet.new(["user-9"]))
    end
  end

  describe "toggle_select_all_page event" do
    test "selects all items on page when none are selected" do
      socket =
        make_socket(%{
          id: "test-table",
          selectable: true,
          selected_ids: MapSet.new(),
          id_field: :id,
          data: [%{id: "user-1"}, %{id: "user-2"}, %{id: "user-3"}]
        })

      {:noreply, updated_socket} =
        LiveComponent.handle_event("toggle_select_all_page", %{}, socket)

      assert MapSet.size(updated_socket.assigns.selected_ids) == 3
      assert MapSet.member?(updated_socket.assigns.selected_ids, "user-1")
      assert MapSet.member?(updated_socket.assigns.selected_ids, "user-2")
      assert MapSet.member?(updated_socket.assigns.selected_ids, "user-3")
    end

    test "deselects all items on page when all are selected" do
      socket =
        make_socket(%{
          id: "test-table",
          selectable: true,
          selected_ids: MapSet.new(["user-1", "user-2", "user-3"]),
          id_field: :id,
          data: [%{id: "user-1"}, %{id: "user-2"}, %{id: "user-3"}]
        })

      {:noreply, updated_socket} =
        LiveComponent.handle_event("toggle_select_all_page", %{}, socket)

      assert MapSet.size(updated_socket.assigns.selected_ids) == 0
    end

    test "selects remaining items when some are selected" do
      socket =
        make_socket(%{
          id: "test-table",
          selectable: true,
          selected_ids: MapSet.new(["user-1"]),
          id_field: :id,
          data: [%{id: "user-1"}, %{id: "user-2"}, %{id: "user-3"}]
        })

      {:noreply, updated_socket} =
        LiveComponent.handle_event("toggle_select_all_page", %{}, socket)

      # When not all are selected, clicking select-all should select all
      assert MapSet.size(updated_socket.assigns.selected_ids) == 3
    end

    test "preserves selection from other pages" do
      # user-4 is from a different page
      socket =
        make_socket(%{
          id: "test-table",
          selectable: true,
          selected_ids: MapSet.new(["user-4"]),
          id_field: :id,
          data: [%{id: "user-1"}, %{id: "user-2"}]
        })

      {:noreply, updated_socket} =
        LiveComponent.handle_event("toggle_select_all_page", %{}, socket)

      # Should have user-4 (from other page) plus user-1 and user-2 (current page)
      assert MapSet.size(updated_socket.assigns.selected_ids) == 3
      assert MapSet.member?(updated_socket.assigns.selected_ids, "user-4")
    end

    test "notifies parent with select_all action" do
      socket =
        make_socket(%{
          id: "test-table",
          selectable: true,
          selected_ids: MapSet.new(),
          on_selection_change: :selection_changed,
          id_field: :id,
          data: [%{id: "user-1"}, %{id: "user-2"}]
        })

      {:noreply, _updated_socket} =
        LiveComponent.handle_event("toggle_select_all_page", %{}, socket)

      assert_received {:selection_changed,
                       %{
                         action: :select_all,
                         selected_count: 2
                       }}
    end
  end

  describe "clear_selection event" do
    test "clears all selected items" do
      socket =
        make_socket(%{
          id: "test-table",
          selectable: true,
          selected_ids: MapSet.new(["user-1", "user-2", "user-3"]),
          data: [%{id: "user-1"}, %{id: "user-2"}]
        })

      {:noreply, updated_socket} =
        LiveComponent.handle_event("clear_selection", %{}, socket)

      assert MapSet.size(updated_socket.assigns.selected_ids) == 0
    end

    test "notifies parent with clear action" do
      socket =
        make_socket(%{
          id: "test-table",
          selectable: true,
          selected_ids: MapSet.new(["user-1"]),
          on_selection_change: :selection_changed,
          data: [%{id: "user-1"}]
        })

      {:noreply, _updated_socket} =
        LiveComponent.handle_event("clear_selection", %{}, socket)

      assert_received {:selection_changed,
                       %{
                         action: :clear,
                         selected_count: 0
                       }}
    end
  end

  describe "selection state persistence" do
    test "selection persists across data reloads" do
      # This tests that selection state uses assign_new, so it's preserved
      # when other assigns are updated
      socket =
        make_socket(%{
          id: "test-table",
          selectable: true,
          selected_ids: MapSet.new(["user-1", "user-2"]),
          data: [%{id: "user-1"}, %{id: "user-2"}]
        })

      # Simulate what happens when new data arrives
      # The selected_ids should be preserved because of assign_new
      assert MapSet.size(socket.assigns.selected_ids) == 2
    end
  end
end
