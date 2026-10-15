defmodule Cinder.Integration.PageClampTest do
  @moduledoc """
  A page past the end of the data is pulled back to the last page that has rows.

  Independent of remembered state — a stale bookmark or a hand-edited `?page=`
  reaches the same dead end — so these tables do not opt into persistence.

  Integration tests here share one accumulating database (`Cinder.ConnCase` sets
  up no sandbox, and three other files bulk-destroy these resources). So the
  collection is given a `query` scoped to an artist generated for the test
  rather than the bare resource: the three rows below are the only ones it can
  ever page over, which makes "page 3 is the last page" true no matter what else
  the suite has left behind.
  """
  use Cinder.ConnCase, async: false

  import Phoenix.ConnTest, only: [get: 2]
  import Phoenix.LiveViewTest

  require Ash.Query

  @table_id "albums"
  @page_count 3

  # One album per page, so each of the three rows is its own page.
  defp album_collection(assigns) do
    ~H"""
    <Cinder.collection
      id={@table_id}
      query={@query}
      url_state={@url_state}
      page_size={1}
      empty_message="No albums found"
    >
      <:col :let={album} field="title" filter sort>{album.title}</:col>
    </Cinder.collection>
    """
  end

  defp path(artist_id) do
    query = Ash.Query.filter(Cinder.Integration.Album, artist_id == ^artist_id)

    Cinder.TestLive.Fixture.register(fn assigns ->
      assigns =
        assigns
        |> Phoenix.Component.assign(:table_id, @table_id)
        |> Phoenix.Component.assign(:query, query)

      album_collection(assigns)
    end)
  end

  defp current_page(view) do
    view
    |> element("[data-key=pagination_current_class]")
    |> render()
    |> String.replace(~r/<[^>]*>/, "")
    |> String.trim()
  end

  setup do
    artist = generate(artist(name: "Clamp Artist"))

    for title <- ["Clamp One", "Clamp Two", "Clamp Three"] do
      generate(album(title: title, genre: :rock, artist_id: artist.id))
    end

    # Clean up after ourselves, as the other integration files do: with no
    # sandbox, rows left behind land in the middle of a title sort elsewhere and
    # push another file's expected first page off page 1. Only our own rows are
    # destroyed, so nothing else loses its fixture.
    on_exit(fn ->
      Cinder.Integration.Album
      |> Ash.Query.filter(artist_id == ^artist.id)
      |> Ash.bulk_destroy!(:destroy, %{}, strategy: :stream)

      Cinder.Integration.Artist
      |> Ash.Query.filter(id == ^artist.id)
      |> Ash.bulk_destroy!(:destroy, %{}, strategy: :stream)
    end)

    %{path: path(artist.id)}
  end

  test "a page past the end is pulled back to the last page with rows", %{
    conn: conn,
    path: path
  } do
    {:ok, view, _html} = live(conn, path <> "?page=9999")

    assert assert_patch(view) =~ "page=#{@page_count}"
    assert current_page(view) == to_string(@page_count)
    # The whole point: rows, instead of an empty table explaining nothing.
    refute render(view) =~ "No albums found"
  end

  test "an in-range page is left exactly where it is", %{conn: conn, path: path} do
    {:ok, view, _html} = live(conn, path <> "?page=2")

    assert current_page(view) == "2"
    refute render(view) =~ "No albums found"
  end

  test "a filter that matches nothing clamps to page 1", %{conn: conn, path: path} do
    # Count 0 is the other edge: the last page is 1, not 0. An empty list renders
    # no pagination at all, so the correction shows in the URL — and page 1 is
    # encoded by leaving `page` out entirely.
    {:ok, view, _html} = live(conn, path <> "?title=zzz-no-such-album&page=5")

    patched = assert_patch(view)

    refute patched =~ "page=5"
    assert patched =~ "title=zzz-no-such-album"
    # The emptiness is the filter's doing, and the empty state says so.
    assert render(view) =~ "No results match the current filters"
  end
end
