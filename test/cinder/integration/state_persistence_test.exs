defmodule Cinder.Integration.StatePersistenceTest do
  @moduledoc """
  End-to-end tests for remembered table state.

  The browser half is stubbed by pushing the hook's event directly: what the
  real hook does is read two stores and push what it found, so a test that
  supplies the payload exercises everything downstream of that.
  """
  use Cinder.ConnCase, async: false

  import Phoenix.ConnTest, only: [get: 2]
  import Phoenix.LiveViewTest

  alias Cinder.StateStorage

  @table_id "albums"

  defp album_collection(assigns) do
    ~H"""
    <Cinder.collection
      id={@table_id}
      resource={Music.Album}
      url_state={@url_state}
      persist_state?={true}
      empty_message="No albums found"
    >
      <:col :let={album} field="title" filter sort search>{album.title}</:col>
      <:col :let={album} field="genre" filter={:select} sort>{album.genre}</:col>
    </Cinder.collection>
    """
  end

  defp path do
    Cinder.TestLive.Fixture.register(fn assigns ->
      assigns = Phoenix.Component.assign(assigns, :table_id, @table_id)
      album_collection(assigns)
    end)
  end

  # One album per page, so the three in the setup span three pages and a
  # remembered page number has somewhere to land.
  defp paged_album_collection(assigns) do
    ~H"""
    <Cinder.collection
      id={@table_id}
      resource={Cinder.Integration.Album}
      url_state={@url_state}
      persist_state?={true}
      page_size={1}
      empty_message="No albums found"
    >
      <:col :let={album} field="title" filter sort search>{album.title}</:col>
      <:col :let={album} field="genre" filter={:select} sort>{album.genre}</:col>
    </Cinder.collection>
    """
  end

  defp paged_path do
    Cinder.TestLive.Fixture.register(fn assigns ->
      assigns = Phoenix.Component.assign(assigns, :table_id, @table_id)
      paged_album_collection(assigns)
    end)
  end

  defp stored(opts) do
    %{
      "durable" => %{
        "v" => StateStorage.version(),
        "params" => Keyword.get(opts, :durable, %{})
      },
      "session" => %{
        "v" => StateStorage.version(),
        "params" => Keyword.get(opts, :session, %{})
      }
    }
  end

  defp hydrate(view, payload) do
    view
    |> element("##{@table_id}-table-state-hook")
    |> render_hook("hydrate_table_state", payload)
  end

  setup do
    artist = generate(artist(name: "Test Artist"))

    for {title, genre} <- [
          {"Dirt", :rock},
          {"Facelift", :rock},
          {"Blue Train", :jazz}
        ] do
      generate(album(title: title, genre: genre, artist_id: artist.id))
    end

    :ok
  end

  describe "the hydration gate" do
    test "the collection is hidden, not empty, until the browser answers", %{conn: conn} do
      {:ok, view, _html} = live(conn, path())

      # The query is not held back — only the paint. A host that never registers
      # the hook still has its rows, which is why this is a class and not an
      # absence of data.
      assert has_element?(view, "td", "Dirt")
      assert gated?(view)
    end

    test "answering releases the gate", %{conn: conn} do
      {:ok, view, _html} = live(conn, path())

      hydrate(view, stored([]))

      refute gated?(view)
      assert has_element?(view, "td", "Dirt")
      assert has_element?(view, "td", "Blue Train")
    end

    test "a browser that never answers is released by the failsafe", %{conn: conn} do
      {:ok, view, _html} = live(conn, path())

      assert gated?(view)

      # The component schedules this for 1s; waiting for it is the point of the test.
      assert eventually(fn -> not gated?(view) end)
    end

    test "a table that does not persist is never gated", %{conn: conn} do
      path =
        Cinder.TestLive.Fixture.register(fn assigns ->
          ~H"""
          <Cinder.collection id="plain" resource={Music.Album} url_state={@url_state}>
            <:col :let={album} field="title" sort>{album.title}</:col>
          </Cinder.collection>
          """
        end)

      {:ok, view, _html} = live(conn, path)

      refute has_element?(view, "[data-key=container_class].invisible")
      refute has_element?(view, "#plain-table-state-hook")
      assert has_element?(view, "td", "Dirt")
    end
  end

  describe "restoring" do
    test "a stored filter narrows the list and lands in the URL", %{conn: conn} do
      {:ok, view, _html} = live(conn, path())

      hydrate(view, stored(session: %{"genre" => "jazz"}))

      assert has_element?(view, "td", "Blue Train")
      refute has_element?(view, "td", "Dirt")
      assert_patched_with(view, "genre=jazz")
    end

    test "a stored sort reorders the list", %{conn: conn} do
      {:ok, view, _html} = live(conn, path())

      hydrate(view, stored(durable: %{"sort" => "-title"}))

      assert_patched_with(view, "sort=-title")
    end

    test "a stored search narrows the list", %{conn: conn} do
      {:ok, view, _html} = live(conn, path())

      hydrate(view, stored(session: %{"search" => "Dirt"}))

      assert has_element?(view, "td", "Dirt")
      refute has_element?(view, "td", "Blue Train")
    end
  end

  describe "writing the stores" do
    test "a sort is pushed to the durable store and a filter to the session one", %{conn: conn} do
      {:ok, view, _html} = live(conn, path())
      hydrate(view, stored([]))

      view
      |> element(~s|[phx-click="toggle_sort"][phx-value-key="title"]|)
      |> render_click()

      assert_push_event(view, "cinder:table_state_changed", payload)
      assert payload["id"] == @table_id
      assert payload["durable"]["params"]["sort"] == "title"
      assert payload["session"]["params"] == %{}
    end

    test "nothing is written before the browser has reported in", %{conn: conn} do
      {:ok, view, _html} = live(conn, path())

      view
      |> element(~s|[phx-click="toggle_sort"][phx-value-key="title"]|)
      |> render_click()

      # Writing now would overwrite the state the hook is still about to send.
      refute_push_event(view, "cinder:table_state_changed", _payload)
    end

    test "a reset writes empty payloads, so it is not undone on the next visit", %{conn: conn} do
      {:ok, view, _html} = live(conn, path())
      hydrate(view, stored(session: %{"genre" => "jazz"}))

      view |> element("[phx-click=clear_all_filters]") |> render_click()

      assert_push_event(view, "cinder:table_state_changed", payload)
      assert payload["session"]["params"] == %{}
    end
  end

  describe "the URL wins" do
    test "a filter in the URL is not displaced by a stored one", %{conn: conn} do
      {:ok, view, _html} = live(conn, path() <> "?genre=rock")

      hydrate(view, stored(session: %{"genre" => "jazz"}))

      assert has_element?(view, "td", "Dirt")
      refute has_element?(view, "td", "Blue Train")
    end

    test "a sort in the URL leaves the stored filter free to apply", %{conn: conn} do
      {:ok, view, _html} = live(conn, path() <> "?sort=title")

      hydrate(view, stored(durable: %{"sort" => "-title"}, session: %{"genre" => "jazz"}))

      assert has_element?(view, "td", "Blue Train")
      refute has_element?(view, "td", "Dirt")
    end
  end

  describe "the empty state names the filter" do
    test "a filter with no matches says so and offers a reset", %{conn: conn} do
      {:ok, view, _html} = live(conn, path())

      html = hydrate(view, stored(session: %{"search" => "nothing matches this"}))

      assert html =~ "No results match the current filters"
      assert html =~ "Reset filters"
      refute html =~ "No albums found"
    end

    test "the reset in the empty state brings the rows back", %{conn: conn} do
      {:ok, view, _html} = live(conn, path())

      hydrate(view, stored(session: %{"search" => "nothing matches this"}))
      refute has_element?(view, "td", "Dirt")

      view
      |> element("td [phx-click=clear_all_filters]")
      |> render_click()

      assert has_element?(view, "td", "Dirt")
      assert has_element?(view, "td", "Blue Train")
    end

    # The row's own reset, not the empty state's: this list still has rows, so
    # what is under test is that a search goes when the filters do. Without that,
    # a reset hands back a list still narrowed by a search box the reader had
    # forgotten, which is the confusion the reset exists to undo.
    test "resetting clears a search as well as the filters", %{conn: conn} do
      {:ok, view, _html} = live(conn, path())

      hydrate(view, stored(session: %{"search" => "Dirt", "genre" => "rock"}))
      assert has_element?(view, "td", "Dirt")
      refute has_element?(view, "td", "Blue Train")

      view
      |> element("[phx-click=clear_all_filters]")
      |> render_click()

      assert has_element?(view, "td", "Blue Train")
    end

    test "an unfiltered empty list keeps the page's own message", %{conn: conn} do
      Ash.bulk_destroy!(Music.Album, :destroy, %{}, strategy: :stream)

      {:ok, view, _html} = live(conn, path())

      html = hydrate(view, stored([]))

      assert html =~ "No albums found"
      refute html =~ "No results match the current filters"
    end
  end

  describe "the page number" do
    test "a stored page is restored and lands in the URL", %{conn: conn} do
      {:ok, view, _html} = live(conn, paged_path())

      hydrate(view, stored(session: %{"page" => "3", "sort" => "title"}))

      assert_patched_with(view, "page=3")
    end

    test "is written to the session store, never the durable one", %{conn: conn} do
      {:ok, view, _html} = live(conn, paged_path())
      hydrate(view, stored([]))

      view |> element(~s|[phx-click="goto_page"][title="Go to page 2"]|) |> render_click()

      assert_push_event(view, "cinder:table_state_changed", payload)
      assert payload["session"]["params"]["page"] == "2"
      refute Map.has_key?(payload["durable"]["params"], "page")
    end

    test "a filter change resets it, so a remembered page cannot outlive its query",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, paged_path())
      hydrate(view, stored(session: %{"page" => "3"}))

      # The page really was restored, so the reset below has something to undo.
      assert_patched_with(view, "page=3")

      view
      |> form(~s|[phx-change="filter_change"]|, %{"filters" => %{"genre" => "rock"}})
      |> render_change()

      assert_push_event(view, "cinder:table_state_changed", payload)
      assert payload["session"]["params"]["genre"] == "rock"
      refute Map.has_key?(payload["session"]["params"], "page")
    end

    test "a reset clears it along with the filters", %{conn: conn} do
      {:ok, view, _html} = live(conn, paged_path())
      hydrate(view, stored(session: %{"genre" => "rock", "page" => "2"}))

      view |> element("[phx-click=clear_all_filters]") |> render_click()

      assert_push_event(view, "cinder:table_state_changed", payload)
      assert payload["session"]["params"] == %{}
    end

    test "a page in the URL is not displaced by a stored one", %{conn: conn} do
      {:ok, view, _html} = live(conn, paged_path() <> "?page=2")

      hydrate(view, stored(session: %{"page" => "3"}))

      # The URL speaks for the whole query group, so the stored page is ignored
      # and the table stays where the link pointed. Asserted on the current-page
      # marker rather than the total, which other tests in this file move.
      assert has_element?(view, "[data-key=pagination_current_class]", "2")
      refute has_element?(view, "[data-key=pagination_current_class]", "3")
    end
  end

  # ── helpers ────────────────────────────────────────────────────────────────

  defp gated?(view), do: has_element?(view, "[data-key=container_class].invisible")

  defp assert_patched_with(view, fragment) do
    assert_patch(view) =~ fragment
  end

  defp eventually(fun, attempts \\ 40) do
    cond do
      fun.() ->
        true

      attempts == 0 ->
        false

      true ->
        Process.sleep(50)
        eventually(fun, attempts - 1)
    end
  end
end
