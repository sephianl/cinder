defmodule Cinder.Integration.AutocompleteSearchTest do
  @moduledoc """
  Covers a search-mode autocomplete filter: the page holds only what `:search` returns,
  searches only when the term or the chosen value changes, and labels a value it was
  handed by the URL.
  """
  use Cinder.ConnCase, async: false
  import Phoenix.ConnTest, only: [get: 2]
  import Phoenix.LiveViewTest, only: [live: 2, element: 2, render_change: 2]

  @titles ["Async Album", "Buffered Album", "Cached Album"]

  setup do
    artist = generate(artist(name: "Artist"))
    for title <- @titles, do: generate(album(title: title, genre: :rock, artist_id: artist.id))

    test_pid = self()

    filter = [
      type: :autocomplete,
      search: fn term ->
        send(test_pid, {:searched, term})
        @titles |> Enum.filter(&String.contains?(&1, term)) |> Enum.take(1) |> Enum.map(&{&1, &1})
      end,
      lookup: fn value ->
        send(test_pid, {:labelled, value})
        if value in @titles, do: value
      end
    ]

    collection = fn assigns ->
      assigns = Phoenix.Component.assign(assigns, :filter, filter)

      ~H"""
      <Cinder.collection resource={Music.Album} url_state={@url_state}>
        <:col :let={album} field="title" filter={@filter}>{album.title}</:col>
      </Cinder.collection>
      """
    end

    on_exit(fn ->
      Ash.bulk_destroy!(Music.Album, :destroy, %{})
      Ash.bulk_destroy!(Music.Artist, :destroy, %{})
    end)

    %{path: Cinder.TestLive.Fixture.register(collection)}
  end

  test "offers only what the search returns, and searches again as the term changes", %{
    conn: conn,
    path: path
  } do
    {:ok, view, html} = live(conn, path)

    assert_received {:searched, ""}
    assert html =~ ~s(value="Async Album")
    refute html =~ ~s(value="Buffered Album")

    html =
      view
      |> element("form[phx-change=filter_change]")
      |> render_change(%{"filters" => %{"title" => "", "title_autocomplete_search" => "Buf"}})

    assert_received {:searched, "Buf"}
    assert html =~ ~s(value="Buffered Album")
    refute html =~ ~s(value="Async Album")
  end

  test "keeps its answer while the term and the chosen value stay the same", %{
    conn: conn,
    path: path
  } do
    {:ok, view, _html} = live(conn, path)
    assert_received {:searched, ""}
    flush_searches()

    view
    |> element("form[phx-change=filter_change]")
    |> render_change(%{"filters" => %{"title" => "", "title_autocomplete_search" => ""}})

    refute_received {:searched, _term}
  end

  test "labels a value from the URL that the search did not return", %{conn: conn, path: path} do
    {:ok, _view, html} = live(conn, path <> "?title=Cached+Album")

    assert_received {:labelled, "Cached Album"}
    assert html =~ ~s(value="Cached Album")
    assert html =~ ~s(value="Async Album")
  end

  defp flush_searches do
    receive do
      {:searched, _term} -> flush_searches()
    after
      0 -> :ok
    end
  end
end
