defmodule Cinder.StateStorage do
  @moduledoc """
  What of a table's state is worth remembering between visits, which store it
  belongs in, and how it merges back under the URL.

  The URL stays the source of truth. This module only ever supplies what the URL
  does not already say.

  ## The split

  State is divided by whether it *hides rows*, not by how long it ought to last:

  * **Sort and page size reorder and resize.** Every row is still there, a wrong
    remembered value shows in the column header at a glance, and undoing it
    costs one click. Being wrong is nearly free, so these are kept
    indefinitely — `localStorage`.
  * **Filter values and the search term subtract rows.** A wrong one is
    invisible *in its effect*: the rows it removed leave no trace, and that cost
    does not decay with time. So these last only as long as the tab —
    `sessionStorage`.
  * **The page number and keyset cursors are kept nowhere.** Returning someone
    to page 7 of a list they last saw a week ago is never what they wanted.

  Companion to `Cinder.ColumnPreferences` and `Cinder.FilterPreferences`, which
  persist table *layout* through the same hook mechanism. This module handles
  state.
  """

  # Bumped when a stored payload's shape changes. A payload stamped with anything
  # else is discarded on read rather than migrated — the fallback is the table's
  # declared defaults, which is already the path a browser with an empty store
  # takes.
  @version 1

  @durable_keys ~w(sort page_size)
  @search_key "search"
  @filter_fields_key "_filter_fields"

  @type store :: :durable | :session
  @type payload :: %{String.t() => map()}

  @doc "The stored-payload shape this build writes and accepts."
  @spec version() :: pos_integer()
  def version, do: @version

  @doc "Keys kept indefinitely, in `localStorage`."
  @spec durable_keys() :: [String.t()]
  def durable_keys, do: @durable_keys

  @doc "Keys kept for the life of the tab, in `sessionStorage`."
  @spec session_keys([String.t()]) :: [String.t()]
  def session_keys(filter_fields) when is_list(filter_fields),
    do: [@search_key | filter_fields]

  @doc """
  Splits an encoded table state into the payload for each store.

  Takes the atom-keyed map `Cinder.UrlManager.encode_state/1` produces and
  returns string-keyed, version-stamped payloads ready to be written to
  `localStorage` and `sessionStorage`. Anything belonging to neither store — the
  page number, keyset cursors, the `_filter_fields` metadata — is dropped.

  Both payloads are always present, so a cleared filter or sort overwrites what
  was stored rather than leaving the old value to be restored next visit.
  """
  @spec split(map()) :: payload()
  def split(encoded_state) when is_map(encoded_state) do
    params = stringify(encoded_state)
    filter_fields = filter_fields(params)

    %{
      "durable" => stamp(Map.take(params, @durable_keys)),
      "session" => stamp(Map.take(params, session_keys(filter_fields)))
    }
  end

  @doc """
  The URL params to restore from storage, or `:none` when there is nothing to add.

  Precedence is **URL > stored > declared default**, applied per *group* rather
  than per key. The groups are the two stores: the view (sort, page size) and the
  query (filters, search). When the URL already carries anything from a group,
  that whole group comes from the URL and none of it is restored — so a shared
  link carrying one filter never silently picks up three more from the reader's
  own storage, and a link carrying only a sort still restores the reader's
  session filters.

  `filter_fields` is the set of filters the table currently manages, so a stored
  value for a column that has since been renamed or removed is ignored rather
  than replayed into a query that can no longer answer it.
  """
  @spec restore(map(), map(), [String.t()]) :: {:ok, map()} | :none
  def restore(url_params, stored, filter_fields)
      when is_map(url_params) and is_map(stored) and is_list(filter_fields) do
    restored =
      %{}
      |> restore_group(url_params, read(stored, "durable"), @durable_keys)
      |> restore_group(url_params, read(stored, "session"), session_keys(filter_fields))

    if map_size(restored) == 0, do: :none, else: {:ok, restored}
  end

  def restore(_url_params, _stored, _filter_fields), do: :none

  # A group the URL speaks for is left alone entirely; otherwise the stored keys
  # of that group are added.
  defp restore_group(acc, url_params, stored, keys) do
    if Enum.any?(keys, &Map.has_key?(url_params, &1)) do
      acc
    else
      Map.merge(acc, Map.take(stored, keys))
    end
  end

  # Absent, malformed, or stamped with a version this build no longer
  # understands all read as "nothing stored" — the same path as a browser that
  # has never stored anything, which is a normal outcome rather than an error.
  defp read(stored, key) do
    case Map.get(stored, key) do
      %{"v" => @version, "params" => params} when is_map(params) -> prune(params)
      _ -> %{}
    end
  end

  defp stamp(params), do: %{"v" => @version, "params" => prune(params)}

  # An empty value carries no state and would only add a dangling `?search=` to
  # the URL, so it is not worth storing or restoring.
  defp prune(params) do
    params
    |> Enum.reject(fn {_key, value} -> value in [nil, "", []] end)
    |> Map.new(fn {key, value} -> {to_string(key), value} end)
  end

  defp stringify(params), do: Map.new(params, fn {key, value} -> {to_string(key), value} end)

  defp filter_fields(params) do
    case Map.get(params, @filter_fields_key) do
      fields when is_binary(fields) and fields != "" -> String.split(fields, ",")
      _ -> []
    end
  end
end
