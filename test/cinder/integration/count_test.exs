defmodule Cinder.Integration.CountTest do
  @moduledoc """
  Covers the `count` option of `pagination` on a mounted collection: how the
  footer reads with a synchronous, asynchronous or disabled total count.
  """
  use Cinder.ConnCase, async: false

  import Phoenix.ConnTest, only: [get: 2]
  import Phoenix.LiveViewTest, only: [live: 2]

  defp collection(pagination) do
    fn assigns ->
      assigns = assign(assigns, :pagination, pagination)

      ~H"""
      <Cinder.collection
        resource={Music.Album}
        url_state={@url_state}
        page_size={2}
        pagination={@pagination}
      >
        <:col :let={album} field="title" sort>{album.title}</:col>
      </Cinder.collection>
      """
    end
  end

  setup do
    artist = generate(artist(name: "Count Artist"))

    for title <- ["Alpha", "Bravo", "Charlie", "Delta", "Echo"] do
      generate(album(title: title, artist_id: artist.id))
    end

    on_exit(fn ->
      Ash.bulk_destroy!(Music.Album, :destroy, %{})
      Ash.bulk_destroy!(Music.Artist, :destroy, %{})
    end)

    :ok
  end

  defp footer(conn, pagination) do
    path = Cinder.TestLive.Fixture.register(collection(pagination)) <> "?sort=title"
    {:ok, _view, html} = live(conn, path)
    html
  end

  test "offset pagination counts by default", %{conn: conn} do
    html = footer(conn, :offset)

    assert html =~ ~r/aria-current="page">\s*1\s*</
    assert html =~ ~s(title="Go to page 3")
    assert html =~ "1–2</span> of 5 items"
  end

  test "an asynchronous count shows the same footer once it arrives", %{conn: conn} do
    html = footer(conn, count: :async)

    assert html =~ ~r/aria-current="page">\s*1\s*</
    assert html =~ ~s(title="Go to page 3")
    assert html =~ "1–2</span> of 5 items"
  end

  test "offset pagination without a count only offers previous and next", %{conn: conn} do
    html = footer(conn, count: false)

    assert html =~ "Alpha"
    assert html =~ "1–2</span> items"
    assert html =~ ~s(title="Next page")
    refute html =~ "</span> of "
    refute html =~ "showing"
    refute html =~ ~s(title="Last page")
  end

  test "keyset pagination without a count only offers previous and next", %{conn: conn} do
    html = footer(conn, mode: :keyset, count: false)

    assert html =~ "Alpha"
    assert html =~ "Next"
    refute html =~ ~r/\d+ items/
  end
end
