defmodule Cinder.ColumnPreferences do
  @moduledoc """
  Pure logic for applying user-edited column visibility and ordering.

  Preferences are a `%{order: [field], hidden: MapSet.t(field)}` map. `order`
  lists reorderable columns in the user's preferred sequence; pinned columns
  (declared with `reorderable: false`) keep their original declared position.
  Hidden columns are removed from the rendered list entirely.

  Columns whose class list contains the bare `hidden` token exist only to host
  a filter or search on a field with no visible body cell (e.g. `class="hidden"`,
  and also responsive forms like `class="hidden md:table-cell"`). These
  filter-only columns never participate in the preferences UI: the user can
  neither show, hide, nor reorder them, and they keep their position among the
  visible columns like a pinned column.
  """

  @type field :: String.t()
  @type t :: %{order: [field] | nil, hidden: MapSet.t(field)}

  @doc "Empty/default preferences — no hidden columns, no custom order."
  @spec empty() :: t()
  def empty, do: %{order: nil, hidden: MapSet.new()}

  @doc """
  Whether a column is display-hidden — its class list contains the bare `hidden`
  token (e.g. `"hidden"` or `"hidden md:table-cell"`).

  Such columns are filter/search-only: they host a filter or search on a field
  but render no visible body cell. They are excluded from the column-preferences
  editor entirely and pinned at their position among the visible columns.
  """
  @spec display_hidden?(map()) :: boolean()
  def display_hidden?(col) do
    col
    |> Map.get(:class)
    |> to_string()
    |> String.split()
    |> Enum.member?("hidden")
  end

  defp pinned?(col), do: not Map.get(col, :reorderable, true) or display_hidden?(col)

  defp hideable?(col), do: Map.get(col, :hideable, true) and not display_hidden?(col)

  @doc """
  Builds initial preferences from the declared columns.

  Columns with `default_visible: false` are added to `hidden` so the user has
  to opt them in via the column-prefs UI.
  """
  @spec from_columns([map()]) :: t()
  def from_columns(columns) do
    hidden =
      columns
      |> Enum.filter(fn col ->
        hideable?(col) && Map.get(col, :default_visible, true) == false
      end)
      |> Enum.map(& &1.field)
      |> MapSet.new()

    %{order: nil, hidden: hidden}
  end

  @doc """
  Returns `columns` with `prefs` applied: hidden columns removed, reorderable
  columns sorted by `prefs.order`, pinned columns held at their declared index.
  """
  @spec apply([map()], t()) :: [map()]
  def apply(columns, %{hidden: hidden, order: order_opt}) do
    visible =
      Enum.reject(columns, fn col ->
        MapSet.member?(hidden, col.field) and not display_hidden?(col)
      end)

    pinned_with_idx =
      visible
      |> Enum.with_index()
      |> Enum.filter(fn {col, _idx} -> pinned?(col) end)
      |> Enum.sort_by(fn {_col, idx} -> idx end)

    reorderable = Enum.reject(visible, &pinned?/1)

    ordered_reorderable = order_reorderable(reorderable, order_opt)

    Enum.reduce(pinned_with_idx, ordered_reorderable, fn {col, idx}, acc ->
      List.insert_at(acc, idx, col)
    end)
  end

  @doc """
  Toggles visibility of a column field, returning new prefs.

  Refuses to hide non-hideable columns. The caller passes the full column list
  so we can validate.
  """
  @spec toggle_hidden(t(), field, [map()]) :: t()
  def toggle_hidden(prefs, field, columns) do
    columns
    |> Enum.find(&(&1.field == field))
    |> do_toggle_hidden(prefs, field)
  end

  defp do_toggle_hidden(nil, prefs, _field), do: prefs

  defp do_toggle_hidden(col, prefs, field) do
    if hideable?(col) do
      %{prefs | hidden: toggle_member(prefs.hidden, field)}
    else
      prefs
    end
  end

  defp toggle_member(set, member) do
    if MapSet.member?(set, member),
      do: MapSet.delete(set, member),
      else: MapSet.put(set, member)
  end

  @doc """
  Replaces the order of reorderable columns.

  Filters `new_order` down to the fields of reorderable columns that exist;
  ignores unknown or pinned fields.
  """
  @spec set_order(t(), [field], [map()]) :: t()
  def set_order(prefs, new_order, columns) when is_list(new_order) do
    valid_fields =
      columns
      |> Enum.reject(&pinned?/1)
      |> Enum.map(& &1.field)
      |> MapSet.new()

    cleaned =
      new_order
      |> Enum.filter(&MapSet.member?(valid_fields, &1))
      |> Enum.uniq()

    %{prefs | order: cleaned}
  end

  @doc "Returns prefs in JSON-friendly form for client persistence."
  @spec to_payload(t()) :: %{order: [field] | nil, hidden: [field]}
  def to_payload(%{order: order, hidden: hidden}) do
    %{order: order, hidden: Enum.sort(MapSet.to_list(hidden))}
  end

  @doc """
  Builds prefs from a client-supplied payload, validating fields against `columns`.

  Unknown fields and pinned fields in `order` are dropped. Unknown fields and
  non-hideable fields in `hidden` are dropped.
  """
  @spec from_payload(map() | nil, [map()]) :: t()
  def from_payload(nil, columns), do: from_columns(columns)

  def from_payload(payload, columns) when is_map(payload) do
    raw_order = Map.get(payload, "order") || Map.get(payload, :order)
    raw_hidden = Map.get(payload, "hidden") || Map.get(payload, :hidden) || []

    base = from_columns(columns)

    base = if is_list(raw_order), do: set_order(base, raw_order, columns), else: base

    hideable_fields =
      columns
      |> Enum.filter(&hideable?/1)
      |> Enum.map(& &1.field)
      |> MapSet.new()

    hidden =
      raw_hidden
      |> Enum.filter(&MapSet.member?(hideable_fields, &1))
      |> MapSet.new()

    %{base | hidden: hidden}
  end

  defp order_reorderable(reorderable, nil), do: reorderable

  defp order_reorderable(reorderable, user_order) when is_list(user_order) do
    by_field = Map.new(reorderable, &{&1.field, &1})

    from_user =
      user_order
      |> Enum.map(&Map.get(by_field, &1))
      |> Enum.reject(&is_nil/1)

    seen = MapSet.new(from_user, & &1.field)
    new_cols = Enum.reject(reorderable, &MapSet.member?(seen, &1.field))

    from_user ++ new_cols
  end
end
