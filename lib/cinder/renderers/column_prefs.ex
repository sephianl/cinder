defmodule Cinder.Renderers.ColumnPrefs do
  @moduledoc """
  Renders the "Edit columns" control: a toggle button, a hydration hook,
  and a slide-in drawer with checkboxes + drag handles for show/hide and
  reorder of declared columns.

  Mounted by the table/list/grid renderers when `column_preferences?` is true.
  The drawer itself is `Cinder.Renderers.PrefsDrawer`, shared with the filter
  editor; this module supplies the column rows and the column event names.
  """

  use Phoenix.Component
  use Cinder.Messages

  alias Cinder.Renderers.PrefsDrawer

  import Cinder.Renderers.Helpers, only: [columns_icon: 1]

  attr(:id, :string, required: true, doc: "Cinder table id; used as localStorage key")
  attr(:myself, :any, required: true, doc: "LiveComponent CID for phx-target")

  attr(:enabled, :boolean,
    default: false,
    doc: "Master switch — equals @column_preferences? from the parent"
  )

  attr(:open?, :boolean, default: false, doc: "Whether the drawer is open")

  attr(:show_button, :boolean,
    default: false,
    doc:
      "Render the standalone top-right \"Columns\" button. The drawer is always reachable via the last action column's header trigger; this appends an extra button."
  )

  attr(:drawer_columns, :list,
    default: [],
    doc:
      "Columns to render in the drawer, in display order: visible columns in the user's preferred order followed by hidden columns at the end."
  )

  attr(:prefs, :map, required: true, doc: "Current %{order, hidden} preferences")
  attr(:theme, :map, required: true, doc: "Resolved theme map")

  def render(assigns) do
    items = Enum.map(assigns.drawer_columns, &drawer_item(&1, assigns.prefs))
    assigns = assign(assigns, :items, items)

    ~H"""
    <div :if={@enabled}
         class={@theme.column_prefs_container_class}
         data-key="column_prefs_container_class">
      <div
        id={"#{@id}-column-prefs-hook"}
        phx-hook="CinderColumnPrefs"
        phx-target={@myself}
        data-cinder-table-id={@id}
        class="hidden"
      />

      <button
        :if={@show_button}
        type="button"
        phx-click="toggle_column_prefs_drawer"
        phx-target={@myself}
        class={@theme.column_prefs_button_class}
        data-key="column_prefs_button_class"
        aria-haspopup="dialog"
        aria-expanded={to_string(@open?)}
      >
        <.columns_icon class={@theme.column_prefs_button_icon_class} />
      </button>

      <PrefsDrawer.render
        id={"#{@id}-column-prefs"}
        table_id={@id}
        myself={@myself}
        theme={@theme}
        open?={@open?}
        title={dgettext("cinder", "Edit columns")}
        items={@items}
        list_hook="CinderColumnSortable"
        close_event="toggle_column_prefs_drawer"
        toggle_event="toggle_column_visibility"
        reset_event="reset_column_preferences"
      />
    </div>
    """
  end

  # The drawer is generic over rows; columns bring the pinned/non-hideable
  # distinction, which maps onto `reorderable?` and `disabled?`.
  defp drawer_item(column, prefs) do
    %{
      field: column.field,
      label: column.label,
      checked?: not MapSet.member?(prefs.hidden, column.field),
      disabled?: not Map.get(column, :hideable, true),
      reorderable?: Map.get(column, :reorderable, true)
    }
  end
end
