defmodule Cinder.Renderers.PrefsDrawer do
  @moduledoc """
  The slide-in drawer shared by the two preference editors — "Edit columns"
  (`Cinder.Renderers.ColumnPrefs`) and "Edit filters"
  (`Cinder.Renderers.FilterPrefs`).

  Owns the chrome only: scrim, panel, header with its close ✕, the sortable
  list of checkbox rows, and the Reset / Done footer. The caller supplies the
  title, the rows, and the event names to push, so the two editors can keep
  separate state while looking and behaving the same.

  Both draw their classes from the `column_prefs_*` theme keys. One drawer, one
  styling: a host theme that restyles the column editor restyles the filter
  editor with it.
  """

  use Phoenix.Component
  use Cinder.Messages

  attr(:id, :string, required: true, doc: "DOM id prefix for the drawer's parts")
  attr(:table_id, :string, required: true, doc: "Cinder table id, for the list's data attribute")
  attr(:myself, :any, required: true, doc: "LiveComponent CID for phx-target")
  attr(:theme, :map, required: true, doc: "Resolved theme map")
  attr(:open?, :boolean, default: false, doc: "Whether the drawer is open")
  attr(:title, :string, required: true, doc: "Drawer heading, also its aria-label")

  attr(:items, :list,
    default: [],
    doc: """
    Rows to render, in display order. Each is a map of `:field`, `:label`,
    `:checked?`, `:disabled?` and `:reorderable?`.
    """
  )

  attr(:list_hook, :string, required: true, doc: "phx-hook driving drag-to-reorder")
  attr(:close_event, :string, required: true, doc: "Event that closes the drawer")
  attr(:toggle_event, :string, required: true, doc: "Event toggling one row's visibility")
  attr(:reset_event, :string, required: true, doc: "Event restoring the defaults")

  def render(assigns) do
    ~H"""
    <div
      class={[
        @theme.column_prefs_backdrop_class,
        backdrop_state_class(@open?)
      ]}
      data-key="column_prefs_backdrop_class"
      phx-click={@close_event}
      phx-target={@myself}
      aria-hidden="true"
    />

    <div class={[
           @theme.column_prefs_panel_class,
           panel_state_class(@open?)
         ]}
         data-key="column_prefs_panel_class"
         role="dialog"
         aria-modal={to_string(@open?)}
         aria-label={@title}
         inert={not @open?}>
        <div class={@theme.column_prefs_header_class}
             data-key="column_prefs_header_class">
          <h2 class={@theme.column_prefs_title_class}
              data-key="column_prefs_title_class">{@title}</h2>
          <button
            type="button"
            phx-click={@close_event}
            phx-target={@myself}
            class={@theme.column_prefs_close_button_class}
            data-key="column_prefs_close_button_class"
            aria-label={dgettext("cinder", "Close")}
          >
            <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24"
                 stroke-width="1.5" stroke="currentColor"
                 class={@theme.column_prefs_close_icon_class}
                 data-key="column_prefs_close_icon_class">
              <path stroke-linecap="round" stroke-linejoin="round" d="M6 18 18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        <ul
          id={"#{@id}-list"}
          phx-hook={@list_hook}
          phx-target={@myself}
          data-cinder-table-id={@table_id}
          class={@theme.column_prefs_list_class}
          data-key="column_prefs_list_class"
        >
          <li
            :for={item <- @items}
            data-field={item.field}
            data-reorderable={to_string(item.reorderable?)}
            class={[
              @theme.column_prefs_item_class,
              item.reorderable? && @theme.column_prefs_item_reorderable_class,
              not item.reorderable? && @theme.column_prefs_item_pinned_class
            ]}
            data-key="column_prefs_item_class"
          >
            <span :if={item.reorderable?}
                  class={@theme.column_prefs_drag_handle_class}
                  data-key="column_prefs_drag_handle_class"
                  aria-hidden="true"
                  title={dgettext("cinder", "Drag to reorder")}>
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"
                   fill="currentColor"
                   class={@theme.column_prefs_drag_handle_icon_class}
                   data-key="column_prefs_drag_handle_icon_class">
                <circle cx="9" cy="6" r="1.5" />
                <circle cx="9" cy="12" r="1.5" />
                <circle cx="9" cy="18" r="1.5" />
                <circle cx="15" cy="6" r="1.5" />
                <circle cx="15" cy="12" r="1.5" />
                <circle cx="15" cy="18" r="1.5" />
              </svg>
            </span>
            <span :if={not item.reorderable?}
                  class={@theme.column_prefs_pinned_icon_class}
                  data-key="column_prefs_pinned_icon_class"
                  aria-hidden="true">
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"
                   fill="currentColor"
                   class={@theme.column_prefs_drag_handle_icon_class}
                   data-key="column_prefs_drag_handle_icon_class">
                <path d="M12 2a3 3 0 0 0-3 3v3H6a2 2 0 0 0-2 2v9a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-9a2 2 0 0 0-2-2h-3V5a3 3 0 0 0-3-3zm-1 6V5a1 1 0 1 1 2 0v3h-2z" />
              </svg>
            </span>

            <input
              id={"#{@id}-cb-#{item.field}"}
              type="checkbox"
              checked={item.checked?}
              disabled={item.disabled?}
              phx-click={@toggle_event}
              phx-value-field={item.field}
              phx-target={@myself}
              class={@theme.column_prefs_checkbox_class}
              data-key="column_prefs_checkbox_class"
            />

            <label for={"#{@id}-cb-#{item.field}"}
                   class={@theme.column_prefs_label_class}
                   data-key="column_prefs_label_class">{item.label}</label>
          </li>
        </ul>

        <div class={@theme.column_prefs_footer_class}
             data-key="column_prefs_footer_class">
          <button
            type="button"
            phx-click={@reset_event}
            phx-target={@myself}
            class={@theme.column_prefs_reset_button_class}
            data-key="column_prefs_reset_button_class"
          >
            {dgettext("cinder", "Reset to defaults")}
          </button>
          <button
            type="button"
            phx-click={@close_event}
            phx-target={@myself}
            class={@theme.column_prefs_done_button_class}
            data-key="column_prefs_done_button_class"
          >
            {dgettext("cinder", "Done")}
          </button>
        </div>
    </div>
    """
  end

  defp panel_state_class(true), do: "translate-x-0"
  defp panel_state_class(false), do: "translate-x-full"

  defp backdrop_state_class(true), do: "opacity-100"
  defp backdrop_state_class(false), do: "opacity-0 pointer-events-none"
end
