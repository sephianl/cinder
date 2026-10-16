defmodule Cinder.Renderers.Pagination do
  @moduledoc """
  Shared pagination component used by Table, List, and Grid renderers.

  Supports two pagination modes:
  - `Ash.Page.Offset` - Traditional page numbers with jump-to-page
  - `Ash.Page.Keyset` - Cursor-based with prev/next navigation (faster for large datasets)

  Uses `AshPhoenix.LiveView` helpers for working with Ash.Page structs directly.
  """

  use Phoenix.Component
  alias Phoenix.LiveView.JS
  use Cinder.Messages

  @doc """
  Checks if pagination controls should be shown based on page.

  Returns true if there are more results than fit on one page.
  """
  def show_pagination?(%Ash.Page.Offset{count: count, limit: limit}), do: count > limit
  def show_pagination?(%Ash.Page.Keyset{count: count, limit: limit}), do: count > limit
  def show_pagination?(_), do: false

  @doc """
  Renders pagination controls with page navigation and optional page size selector.

  Handles the wrapper div and conditional display internally.
  Returns empty content if pagination should not be shown.

  ## Required assigns
  - `page` - An `Ash.Page.Offset`, `Ash.Page.Keyset`, or nil
  - `page_size_config` - Map with page size configuration
  - `theme` - Theme configuration map
  - `myself` - LiveComponent reference for event targeting
  - `show_pagination` - Boolean to enable/disable pagination (default: true)
  """
  def render(assigns) do
    show = Map.get(assigns, :show_pagination, true) and show_pagination?(assigns.page)

    if show do
      # Use pagination_mode (if provided) to determine UI, not just page struct type.
      # This handles the case where keyset mode returns Ash.Page.Offset on the first page
      # (when no cursor is provided yet).
      pagination_mode = Map.get(assigns, :pagination_mode, :offset)

      case pagination_mode do
        :keyset -> render_keyset(assigns)
        :offset -> render_offset(assigns)
      end
    else
      render_empty(assigns)
    end
  end

  defp render_empty(assigns) do
    ~H"""
    """
  end

  # Offset pagination (traditional page numbers)
  # In offset mode, we always pass `offset:` to Ash.Query.page, so Ash returns Ash.Page.Offset
  defp render_offset(assigns) do
    %Ash.Page.Offset{} = page = assigns.page
    page_number = AshPhoenix.LiveView.page_number(page) + 1
    total_pages = if page.count > 0, do: ceil(page.count / page.limit), else: 1
    start_index = page.offset + 1
    end_index = min(page.offset + length(page.results), page.count)
    page_range = build_page_range(page_number, total_pages)

    # Split on {range} so the range keeps the count class while the sentence
    # stays one translatable string (same trick as the page size selector).
    [info_before, info_after] =
      dgettext("cinder", "Showing {range} of %{total} items", total: page.count)
      |> String.split("{range}")

    assigns =
      assigns
      |> assign(:page_range, page_range)
      |> assign(:info_before, info_before)
      |> assign(:info_after, info_after)
      |> assign(:page_number, page_number)
      |> assign(:total_pages, total_pages)
      |> assign(:start_index, if(page.count > 0, do: start_index, else: 0))
      |> assign(:end_index, if(page.count > 0, do: end_index, else: 0))
      |> assign(:total_count, page.count)
      |> assign(:has_prev, AshPhoenix.LiveView.prev_page?(page))
      |> assign(:has_next, AshPhoenix.LiveView.next_page?(page))

    ~H"""
    <div class={@theme.pagination_wrapper_class} data-key="pagination_wrapper_class">
      <div class={@theme.pagination_container_class} data-key="pagination_container_class">
      <!-- Left side: what you are looking at, and how much of it per page -->
      <div class="flex flex-wrap items-center gap-x-6 gap-y-2">
        <div class={@theme.pagination_info_class} data-key="pagination_info_class">
          {@info_before}<span class={@theme.pagination_count_class} data-key="pagination_count_class">{@start_index}&ndash;{@end_index}</span>{@info_after}
        </div>

        <div :if={@page_size_config.configurable} class={@theme.page_size_container_class} data-key="page_size_container_class">
          <.page_size_selector page_size_config={@page_size_config} theme={@theme} myself={@myself} id={@id} />
        </div>
      </div>

      <!-- Right side: where you are in it -->
      <div>
        <!-- Page navigation -->
        <%!-- First and last page are always in the range, so this needs no
             jump-to-end buttons: Prev/Next, the numbers, and an ellipsis
             wherever the range skips. --%>
        <div class={@theme.pagination_nav_class} data-key="pagination_nav_class">
          <button
            phx-click="goto_page"
            phx-value-page={max(@page_number - 1, 1)}
            phx-target={@myself}
            class={@theme.pagination_step_class}
            data-key="pagination_step_class"
            disabled={!@has_prev}
            title={dgettext("cinder", "Previous page")}
          >
            &lsaquo; {dgettext("cinder", "Previous")}
          </button>

          <!-- Page numbers -->
          <span :for={entry <- @page_range} class="inline-flex">
            <span
              :if={entry == :ellipsis}
              class={@theme.pagination_ellipsis_class}
              data-key="pagination_ellipsis_class"
              aria-hidden="true"
            >
              &hellip;
            </span>
            <span
              :if={entry == @page_number}
              class={@theme.pagination_current_class}
              data-key="pagination_current_class"
              aria-current="page"
            >
              {entry}
            </span>
            <button
              :if={entry != :ellipsis and entry != @page_number}
              phx-click="goto_page"
              phx-value-page={entry}
              phx-target={@myself}
              class={@theme.pagination_button_class}
              data-key="pagination_button_class"
              title={dgettext("cinder", "Go to page %{page}", %{page: entry})}
            >
              {entry}
            </button>
          </span>

          <button
            phx-click="goto_page"
            phx-value-page={min(@page_number + 1, @total_pages)}
            phx-target={@myself}
            class={@theme.pagination_step_class}
            data-key="pagination_step_class"
            disabled={!@has_next}
            title={dgettext("cinder", "Next page")}
          >
            {dgettext("cinder", "Next")} &rsaquo;
          </button>
        </div>
      </div>
      </div>
    </div>
    """
  end

  # Keyset pagination (cursor-based prev/next)
  # Note: "First" and "Last" buttons are not included because keyset pagination
  # doesn't support arbitrary page jumps - only sequential navigation.
  #
  # Why we handle both Ash.Page.Keyset and Ash.Page.Offset here:
  # On the first page (no cursor), there's no way to force keyset mode - Ash falls back
  # to app config. New Ash installs default to keyset, but older apps may default to offset.
  # Once navigation begins (after/before cursor provided), Ash returns Keyset.
  defp render_keyset(assigns) do
    page = assigns.page

    has_prev = has_previous_keyset_page?(page)
    has_next = has_next_keyset_page?(page)

    assigns =
      assigns
      |> assign(:total_count, page.count)
      |> assign(:has_prev, has_prev)
      |> assign(:has_next, has_next)

    ~H"""
    <div class={@theme.pagination_wrapper_class} data-key="pagination_wrapper_class">
      <div class={@theme.pagination_container_class} data-key="pagination_container_class">
      <!-- Left side: what you are looking at, and how much of it per page -->
      <div class="flex flex-wrap items-center gap-x-6 gap-y-2">
        <div class={@theme.pagination_info_class} data-key="pagination_info_class">
          {dgettext("cinder", "%{total} items", total: @total_count)}
        </div>

        <div :if={@page_size_config.configurable} class={@theme.page_size_container_class} data-key="page_size_container_class">
          <.page_size_selector page_size_config={@page_size_config} theme={@theme} myself={@myself} id={@id} />
        </div>
      </div>

      <!-- Right side: where you are in it -->
      <div>
        <!-- Keyset navigation: Prev / Next only -->
        <div class={@theme.pagination_nav_class} data-key="pagination_nav_class">
          <!-- Previous page -->
          <button
            phx-click="prev_page"
            phx-target={@myself}
            class={@theme.pagination_step_class}
            data-key="pagination_step_class"
            disabled={!@has_prev}
            title={dgettext("cinder", "Previous page")}
          >
            &lsaquo; {dgettext("cinder", "Previous")}
          </button>

          <!-- Next page -->
          <button
            phx-click="next_page"
            phx-target={@myself}
            class={@theme.pagination_step_class}
            data-key="pagination_step_class"
            disabled={!@has_next}
            title={dgettext("cinder", "Next page")}
          >
            {dgettext("cinder", "Next")} &rsaquo;
          </button>
        </div>
      </div>
      </div>
    </div>
    """
  end

  defp page_size_selector(assigns) do
    dropdown_id = "#{assigns.id}-page-size-options"
    # Split the translated string on {selector} to allow flexible word order
    [before_selector, after_selector] =
      dgettext("cinder", "Show {selector} per page")
      |> String.split("{selector}")

    assigns =
      assigns
      |> assign(:dropdown_id, dropdown_id)
      |> assign(:before_selector, before_selector)
      |> assign(:after_selector, after_selector)

    ~H"""
    <div class="flex items-center space-x-2">
      <span :if={@before_selector != ""} class={@theme.page_size_label_class} data-key="page_size_label_class">
        {@before_selector}
      </span>
      <div class="relative">
        <button
          type="button"
          class={@theme.page_size_dropdown_class}
          data-key="page_size_dropdown_class"
          phx-click={JS.toggle(to: "##{@dropdown_id}")}
          aria-haspopup="true"
          aria-expanded="false"
        >
          {@page_size_config.selected_page_size}
          <svg class="w-4 h-4 ml-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7"></path>
          </svg>
        </button>
        <div
          id={@dropdown_id}
          class={["absolute bottom-full left-0 mb-1 z-50 hidden", @theme.page_size_dropdown_container_class]}
          data-key="page_size_dropdown_container_class"
          phx-click-away={JS.hide(to: "##{@dropdown_id}")}
        >
          <button
            :for={option <- @page_size_config.page_size_options}
            type="button"
            class={[
              @theme.page_size_option_class,
              (@page_size_config.selected_page_size == option && @theme.page_size_selected_class || "")
            ]}
            data-key="page_size_option_class"
            phx-click={JS.push("change_page_size") |> JS.hide(to: "##{@dropdown_id}")}
            phx-value-page_size={option}
            phx-target={@myself}
          >
            {option}
          </button>
        </div>
      </div>
      <span :if={@after_selector != ""} class={@theme.page_size_label_class} data-key="page_size_label_class">
        {@after_selector}
      </span>
    </div>
    """
  end

  # Page one and the last page are always reachable; `:ellipsis` marks a gap the
  # range skips. At most seven slots, so the nav never grows with the dataset.
  defp build_page_range(_current_page, total_pages) when total_pages <= 7,
    do: Enum.to_list(1..max(total_pages, 1))

  defp build_page_range(current_page, total_pages) when current_page <= 3,
    do: [1, 2, 3, :ellipsis, total_pages]

  defp build_page_range(current_page, total_pages) when current_page >= total_pages - 2,
    do: [1, :ellipsis, total_pages - 2, total_pages - 1, total_pages]

  defp build_page_range(current_page, total_pages),
    do: [1, :ellipsis, current_page - 1, current_page, current_page + 1, :ellipsis, total_pages]

  # Check if there's a previous page in keyset mode.
  # - If we used `after` cursor (forward navigation): there's always a previous page
  # - If we used `before` cursor (backward navigation): `more?` tells us if there's more behind
  # - If neither: we're on the first page
  defp has_previous_keyset_page?(%Ash.Page.Keyset{
         after: after_cursor,
         before: before_cursor,
         more?: more?
       }) do
    cond do
      not is_nil(after_cursor) -> true
      not is_nil(before_cursor) -> more?
      true -> false
    end
  end

  defp has_previous_keyset_page?(%Ash.Page.Offset{offset: offset}), do: offset > 0

  # Check if there's a next page in keyset mode.
  # - If we used `before` cursor (backward navigation): there's always a next page (we came from there)
  # - If we used `after` cursor or no cursor: `more?` tells us if there's more ahead
  defp has_next_keyset_page?(%Ash.Page.Keyset{before: before_cursor})
       when not is_nil(before_cursor),
       do: true

  defp has_next_keyset_page?(%Ash.Page.Keyset{more?: more?}), do: more?

  defp has_next_keyset_page?(%Ash.Page.Offset{more?: more?}), do: more?
end
