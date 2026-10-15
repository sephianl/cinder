defmodule Cinder.StateStorageTest do
  use ExUnit.Case, async: true

  alias Cinder.StateStorage

  defp stored(durable, session) do
    %{
      "durable" => %{"v" => StateStorage.version(), "params" => durable},
      "session" => %{"v" => StateStorage.version(), "params" => session}
    }
  end

  describe "split/1" do
    test "sends sort and page size to the durable store" do
      %{"durable" => %{"params" => params}} =
        StateStorage.split(%{sort: "-code", page_size: "50"})

      assert params == %{"sort" => "-code", "page_size" => "50"}
    end

    test "sends search and filter values to the session store" do
      %{"session" => %{"params" => params}} =
        StateStorage.split(%{
          search: "widget",
          zone: "B-12",
          _filter_fields: "zone,status"
        })

      assert params == %{"search" => "widget", "zone" => "B-12"}
    end

    test "keeps the page number with the filters, and keyset cursors nowhere" do
      split = StateStorage.split(%{page: "7", after: "abc", before: "xyz", sort: "-code"})

      assert split["durable"]["params"] == %{"sort" => "-code"}
      assert split["session"]["params"] == %{"page" => "7"}
    end

    test "stores no page at all on page 1" do
      # `encode_state/1` omits the page entirely on page 1, so paging back to the
      # first page overwrites the stored page rather than leaving the old one to
      # be restored.
      split = StateStorage.split(%{sort: "-code"})

      refute Map.has_key?(split["session"]["params"], "page")
    end

    test "drops the filter-fields metadata rather than storing it" do
      split = StateStorage.split(%{zone: "B-12", _filter_fields: "zone"})

      refute Map.has_key?(split["session"]["params"], "_filter_fields")
      refute Map.has_key?(split["durable"]["params"], "_filter_fields")
    end

    test "a filter the table manages but is not set is not stored" do
      %{"session" => %{"params" => params}} =
        StateStorage.split(%{zone: "", _filter_fields: "zone,status"})

      assert params == %{}
    end

    test "both payloads are always written, so a cleared value overwrites the old one" do
      split = StateStorage.split(%{})

      assert split["durable"]["params"] == %{}
      assert split["session"]["params"] == %{}
    end

    test "stamps each payload with the current version" do
      split = StateStorage.split(%{sort: "-code"})

      assert split["durable"]["v"] == StateStorage.version()
      assert split["session"]["v"] == StateStorage.version()
    end
  end

  describe "restore/3 — nothing to do" do
    test "returns :none when the stores are empty" do
      assert StateStorage.restore(%{}, stored(%{}, %{}), ["zone"]) == :none
    end

    test "returns :none when nothing is stored at all" do
      assert StateStorage.restore(%{}, %{}, ["zone"]) == :none
    end

    test "returns :none for a non-map payload" do
      assert StateStorage.restore(%{}, "nonsense", ["zone"]) == :none
    end
  end

  describe "restore/3 — the URL wins per group" do
    test "restores both groups when the URL says nothing" do
      assert {:ok, restored} =
               StateStorage.restore(
                 %{},
                 stored(%{"sort" => "-code"}, %{"zone" => "B-12"}),
                 ["zone"]
               )

      assert restored == %{"sort" => "-code", "zone" => "B-12"}
    end

    test "a sort in the URL suppresses the stored sort but not the stored filters" do
      assert {:ok, restored} =
               StateStorage.restore(
                 %{"sort" => "name"},
                 stored(%{"sort" => "-code"}, %{"zone" => "B-12"}),
                 ["zone"]
               )

      assert restored == %{"zone" => "B-12"}
    end

    test "a filter in the URL suppresses every stored filter, not just that one" do
      assert {:ok, restored} =
               StateStorage.restore(
                 %{"status" => "open"},
                 stored(%{"sort" => "-code"}, %{"zone" => "B-12", "batch" => "7"}),
                 ["zone", "status", "batch"]
               )

      assert restored == %{"sort" => "-code"}
    end

    test "a search in the URL counts as the query group being spoken for" do
      assert StateStorage.restore(
               %{"search" => "widget"},
               stored(%{}, %{"zone" => "B-12"}),
               ["zone"]
             ) == :none
    end

    test "a page size in the URL suppresses the stored sort too" do
      assert StateStorage.restore(
               %{"page_size" => "100"},
               stored(%{"sort" => "-code"}, %{}),
               ["zone"]
             ) == :none
    end

    test "a page number in the URL speaks for the query group" do
      # A link to page 3 describes a position in the list the sender was looking
      # at. Restoring the reader's own filters underneath it would renumber the
      # pages, so page 3 would show rows the sender never saw. The sort still
      # restores — it is in the other group.
      assert {:ok, restored} =
               StateStorage.restore(
                 %{"page" => "3"},
                 stored(%{"sort" => "-code"}, %{"zone" => "B-12"}),
                 ["zone"]
               )

      assert restored == %{"sort" => "-code"}
    end

    test "restores the page together with the filters it was paged under" do
      assert {:ok, restored} =
               StateStorage.restore(
                 %{},
                 stored(%{}, %{"zone" => "B-12", "page" => "3"}),
                 ["zone"]
               )

      assert restored == %{"zone" => "B-12", "page" => "3"}
    end

    test "a filter in the URL blocks the stored page along with the stored filters" do
      # Same group, so it goes all or nothing: a link carrying one filter must
      # not pick up a page number belonging to a different query.
      assert {:ok, restored} =
               StateStorage.restore(
                 %{"zone" => "A-01"},
                 stored(%{"sort" => "-code"}, %{"zone" => "B-12", "page" => "3"}),
                 ["zone"]
               )

      assert restored == %{"sort" => "-code"}
    end
  end

  describe "restore/3 — stale and malformed payloads" do
    test "ignores a stored filter for a field the table no longer manages" do
      assert {:ok, restored} =
               StateStorage.restore(
                 %{},
                 stored(%{}, %{"zone" => "B-12", "retired_column" => "x"}),
                 ["zone"]
               )

      assert restored == %{"zone" => "B-12"}
    end

    test "discards a payload stamped with another version" do
      payload = %{
        "durable" => %{"v" => StateStorage.version() + 1, "params" => %{"sort" => "-code"}},
        "session" => %{"v" => StateStorage.version(), "params" => %{"zone" => "B-12"}}
      }

      assert {:ok, restored} = StateStorage.restore(%{}, payload, ["zone"])
      assert restored == %{"zone" => "B-12"}
    end

    test "discards an unstamped payload" do
      assert StateStorage.restore(%{}, %{"durable" => %{"sort" => "-code"}}, []) == :none
    end

    test "discards a payload whose params are not a map" do
      payload = %{"durable" => %{"v" => StateStorage.version(), "params" => "-code"}}

      assert StateStorage.restore(%{}, payload, []) == :none
    end

    test "ignores an empty stored value rather than restoring a dangling param" do
      assert StateStorage.restore(%{}, stored(%{}, %{"search" => ""}), []) == :none
    end
  end

  describe "round trip" do
    test "what split writes, restore reads back" do
      encoded = %{
        sort: "-code",
        page_size: "50",
        search: "widget",
        zone: "B-12",
        page: "4",
        _filter_fields: "zone,status"
      }

      assert {:ok, restored} =
               StateStorage.restore(%{}, StateStorage.split(encoded), ["zone", "status"])

      assert restored == %{
               "sort" => "-code",
               "page_size" => "50",
               "search" => "widget",
               "zone" => "B-12",
               "page" => "4"
             }
    end
  end
end
