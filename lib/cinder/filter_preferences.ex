defmodule Cinder.FilterPreferences do
  @moduledoc """
  Pure logic for applying user-edited filter visibility and ordering.

  The filter row is editable in the same way the column list is, but entirely
  separately: preferences are a `%{order: [field], hidden: MapSet.t(field)}` map
  over the *filterable* fields, with their own storage key and their own drawer.
  Changing which columns the table shows does not touch this map.

  One thing differs from `Cinder.ColumnPreferences`: **nothing is pinned.** Every
  filter can be hidden and reordered, so there is no pinned/hideable distinction
  to honour.

  Filters start shown unless a column declares `filter_default_visible: false`,
  which ships that filter in the drawer instead — for a table that wants a short
  row by default without putting its other filters out of reach.

  The row becomes editable once there is something worth editing: more than three
  filters (search excluded), or any filter that ships hidden. See `editable?/1`.
  """

  @type field :: String.t()
  @type t :: %{order: [field] | nil, hidden: MapSet.t(field)}

  # Up to and including this many filters, the row is short enough to show
  # whole: no edit button, no drawer, nothing to persist.
  @selector_threshold 3

  @doc "Empty preferences — every filter shown, in column order."
  @spec empty() :: t()
  def empty, do: %{order: nil, hidden: MapSet.new()}

  @spec from_columns([map()]) :: t()
  def from_columns(filterable_columns) do
    hidden =
      filterable_columns
      |> Enum.filter(&(Map.get(&1, :filter_default_visible, true) == false))
      |> Enum.map(& &1.field)
      |> MapSet.new()

    %{order: nil, hidden: hidden}
  end

  @doc "The filter count above which the row becomes editable on length alone."
  @spec selector_threshold() :: pos_integer()
  def selector_threshold, do: @selector_threshold

  @doc """
  Whether the row has something worth editing, and so earns its button.

  True when there are more filters than the threshold — search is not a
  filterable column, so it never counts — or when any filter ships hidden, since
  the drawer is the only way to reach one of those.
  """
  @spec editable?([map()]) :: boolean()
  def editable?(filterable_columns) when is_list(filterable_columns) do
    length(filterable_columns) > @selector_threshold or
      Enum.any?(filterable_columns, &(Map.get(&1, :filter_default_visible, true) == false))
  end

  @doc """
  Returns `columns` in the operator's preferred order.

  Nothing is removed: a hidden filter still needs its value built so the row can
  show it anyway when it carries one (see `Cinder.Controls.render_filter_row/1`).
  Fields the preferences don't mention — a newly declared filter — keep their
  declared order at the end.
  """
  @spec order([map()], t()) :: [map()]
  def order(columns, %{order: nil}), do: columns

  def order(columns, %{order: user_order}) when is_list(user_order) do
    by_field = Map.new(columns, &{&1.field, &1})

    from_user =
      user_order
      |> Enum.map(&Map.get(by_field, &1))
      |> Enum.reject(&is_nil/1)

    seen = MapSet.new(from_user, & &1.field)

    from_user ++ Enum.reject(columns, &MapSet.member?(seen, &1.field))
  end

  @doc "Whether `field`'s filter is hidden from the row."
  @spec hidden?(t(), field) :: boolean()
  def hidden?(%{hidden: hidden}, field), do: MapSet.member?(hidden, field)

  @doc """
  Toggles whether `field`'s filter shows in the row, returning new preferences.

  Fields that aren't filterable columns are ignored, so a stale payload or a
  renamed field cannot hide something that no longer exists.
  """
  @spec toggle_hidden(t(), field, [map()]) :: t()
  def toggle_hidden(prefs, field, columns) do
    if known?(field, columns) do
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
  Replaces the filter order, dropping unknown fields.
  """
  @spec set_order(t(), [field], [map()]) :: t()
  def set_order(prefs, new_order, columns) when is_list(new_order) do
    cleaned =
      new_order
      |> Enum.filter(&known?(&1, columns))
      |> Enum.uniq()

    %{prefs | order: cleaned}
  end

  @doc "Returns preferences in JSON-friendly form for client persistence."
  @spec to_payload(t()) :: %{order: [field] | nil, hidden: [field]}
  def to_payload(%{order: order, hidden: hidden}) do
    %{order: order, hidden: Enum.sort(MapSet.to_list(hidden))}
  end

  @doc """
  Builds preferences from a client-supplied payload, validating against `columns`.

  Unknown fields are dropped from both `order` and `hidden`. A payload with no
  `hidden` key falls back to the declared defaults; one that carries a `hidden`
  list replaces them, so a user who reveals a filter that ships hidden keeps it.
  """
  @spec from_payload(map() | nil, [map()]) :: t()
  def from_payload(nil, columns), do: from_columns(columns)

  def from_payload(payload, columns) when is_map(payload) do
    raw_order = Map.get(payload, "order") || Map.get(payload, :order)
    raw_hidden = Map.get(payload, "hidden") || Map.get(payload, :hidden)

    base = from_columns(columns)

    base =
      if is_list(raw_hidden) do
        %{base | hidden: raw_hidden |> Enum.filter(&known?(&1, columns)) |> MapSet.new()}
      else
        base
      end

    if is_list(raw_order), do: set_order(base, raw_order, columns), else: base
  end

  def from_payload(_payload, columns), do: from_columns(columns)

  defp known?(field, columns), do: Enum.any?(columns, &(&1.field == field))
end
