defmodule Cinder.FilterPreferencesTest do
  use ExUnit.Case, async: true

  alias Cinder.FilterPreferences

  defp col(field, opts \\ []) do
    %{
      field: field,
      label: String.capitalize(field),
      filter_default_visible: Keyword.get(opts, :filter_default_visible, true)
    }
  end

  defp cols(fields), do: Enum.map(fields, &col/1)

  describe "empty/0" do
    test "starts with every filter shown and no custom order" do
      assert FilterPreferences.empty() == %{order: nil, hidden: MapSet.new()}
    end
  end

  describe "from_columns/1" do
    test "everything shown when nothing declares otherwise" do
      assert FilterPreferences.from_columns(cols(["a", "b"])) == FilterPreferences.empty()
    end

    test "a filter declared filter_default_visible: false starts hidden" do
      columns = [col("a"), col("b", filter_default_visible: false)]

      prefs = FilterPreferences.from_columns(columns)

      refute FilterPreferences.hidden?(prefs, "a")
      assert FilterPreferences.hidden?(prefs, "b")
    end
  end

  describe "editable?/1" do
    test "is false up to the threshold and true beyond it" do
      refute FilterPreferences.editable?(cols(["a", "b", "c"]))
      assert FilterPreferences.editable?(cols(["a", "b", "c", "d"]))
    end

    test "an empty filter list never turns the editor on" do
      refute FilterPreferences.editable?([])
    end

    # Otherwise a filter shipped hidden on a short row would be unreachable.
    test "a short row with a hidden filter is still editable" do
      columns = [col("a"), col("b", filter_default_visible: false)]

      assert FilterPreferences.editable?(columns)
    end
  end

  describe "order/2" do
    test "leaves the declared order alone when nothing was dragged" do
      columns = cols(["a", "b", "c"])

      assert FilterPreferences.order(columns, FilterPreferences.empty()) == columns
    end

    test "follows the stored order" do
      columns = cols(["a", "b", "c"])
      prefs = %{order: ["c", "a", "b"], hidden: MapSet.new()}

      assert FilterPreferences.order(columns, prefs) |> Enum.map(& &1.field) == ["c", "a", "b"]
    end

    test "a newly declared filter lands at the end rather than disappearing" do
      columns = cols(["a", "b", "new"])
      prefs = %{order: ["b", "a"], hidden: MapSet.new()}

      assert FilterPreferences.order(columns, prefs) |> Enum.map(& &1.field) == ["b", "a", "new"]
    end

    test "a stored field that no longer exists is ignored" do
      columns = cols(["a", "b"])
      prefs = %{order: ["gone", "b", "a"], hidden: MapSet.new()}

      assert FilterPreferences.order(columns, prefs) |> Enum.map(& &1.field) == ["b", "a"]
    end

    test "hidden filters stay in the list — the row decides what to render" do
      columns = cols(["a", "b"])
      prefs = %{order: nil, hidden: MapSet.new(["a"])}

      assert FilterPreferences.order(columns, prefs) |> Enum.map(& &1.field) == ["a", "b"]
    end
  end

  describe "toggle_hidden/3" do
    test "hides then shows again" do
      columns = cols(["a", "b"])

      prefs = FilterPreferences.toggle_hidden(FilterPreferences.empty(), "a", columns)
      assert FilterPreferences.hidden?(prefs, "a")

      prefs = FilterPreferences.toggle_hidden(prefs, "a", columns)
      refute FilterPreferences.hidden?(prefs, "a")
    end

    test "ignores a field that is not a filterable column" do
      columns = cols(["a"])

      prefs = FilterPreferences.toggle_hidden(FilterPreferences.empty(), "nope", columns)

      assert prefs.hidden == MapSet.new()
    end
  end

  describe "set_order/3" do
    test "drops unknown fields and duplicates" do
      columns = cols(["a", "b"])

      prefs =
        FilterPreferences.set_order(FilterPreferences.empty(), ["b", "gone", "a", "b"], columns)

      assert prefs.order == ["b", "a"]
    end
  end

  describe "payload round-trip" do
    test "to_payload sorts hidden for a stable localStorage entry" do
      prefs = %{order: ["b", "a"], hidden: MapSet.new(["b", "a"])}

      assert FilterPreferences.to_payload(prefs) == %{order: ["b", "a"], hidden: ["a", "b"]}
    end

    test "from_payload restores what to_payload wrote" do
      columns = cols(["a", "b", "c"])
      prefs = %{order: ["c", "a", "b"], hidden: MapSet.new(["b"])}

      restored =
        prefs
        |> FilterPreferences.to_payload()
        |> then(&%{"order" => &1.order, "hidden" => &1.hidden})
        |> FilterPreferences.from_payload(columns)

      assert restored == prefs
    end

    test "nil and junk payloads fall back to the declared defaults" do
      columns = [col("a"), col("b", filter_default_visible: false)]
      declared = FilterPreferences.from_columns(columns)

      assert FilterPreferences.from_payload(nil, columns) == declared
      assert FilterPreferences.from_payload("junk", columns) == declared
    end

    test "a stored hidden list wins over the declared defaults" do
      # The user revealed the filter the page ships hidden; that choice sticks.
      columns = [col("a"), col("b", filter_default_visible: false)]

      prefs = FilterPreferences.from_payload(%{"hidden" => []}, columns)

      refute FilterPreferences.hidden?(prefs, "b")
    end

    test "a payload with no hidden key keeps the declared defaults" do
      columns = [col("a"), col("b", filter_default_visible: false)]

      prefs = FilterPreferences.from_payload(%{"order" => ["b", "a"]}, columns)

      assert FilterPreferences.hidden?(prefs, "b")
      assert prefs.order == ["b", "a"]
    end

    test "fields that no longer exist are dropped from a stored payload" do
      columns = cols(["a"])

      prefs =
        FilterPreferences.from_payload(%{"order" => ["gone"], "hidden" => ["gone"]}, columns)

      assert prefs == %{order: [], hidden: MapSet.new()}
    end
  end
end
