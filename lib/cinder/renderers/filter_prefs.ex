defmodule Cinder.Renderers.FilterPrefs do
  @moduledoc """
  Renders the "Edit filters" control: a hydration hook and a slide-in drawer
  with checkboxes + drag handles for show/hide and reorder of the filter row.

  Mounted by the table/list/grid renderers once a table has enough filters to
  be worth trimming (`Cinder.FilterPreferences.selector?/1`). The button that
  opens it lives in the filter row itself —
  `Cinder.Controls.render_filter_row/1` — so it sits with the controls it
  edits rather than with the table chrome.

  The drawer is `Cinder.Renderers.PrefsDrawer`, shared with the column editor;
  this module supplies the filter rows and the filter event names. Filter
  preferences are their own map with their own storage key: editing the filter
  row never touches which columns the table shows.
  """

  use Phoenix.Component
  use Cinder.Messages

  alias Cinder.Renderers.PrefsDrawer

  attr(:id, :string, required: true, doc: "Cinder table id; used as localStorage key")
  attr(:myself, :any, required: true, doc: "LiveComponent CID for phx-target")

  attr(:enabled, :boolean,
    default: false,
    doc: "Master switch — true once the filter row is long enough to be editable"
  )

  attr(:open?, :boolean, default: false, doc: "Whether the drawer is open")

  attr(:drawer_filters, :list,
    default: [],
    doc: "Every filterable column, in the user's preferred order."
  )

  attr(:prefs, :map, required: true, doc: "Current %{order, hidden} preferences")
  attr(:theme, :map, required: true, doc: "Resolved theme map")

  def render(assigns) do
    items = Enum.map(assigns.drawer_filters, &drawer_item(&1, assigns.prefs))
    assigns = assign(assigns, :items, items)

    ~H"""
    <div :if={@enabled}
         class={@theme.filter_prefs_container_class}
         data-key="filter_prefs_container_class">
      <div
        id={"#{@id}-filter-prefs-hook"}
        phx-hook="CinderFilterPrefs"
        phx-target={@myself}
        data-cinder-table-id={@id}
        class="hidden"
      />

      <PrefsDrawer.render
        id={"#{@id}-filter-prefs"}
        table_id={@id}
        myself={@myself}
        theme={@theme}
        open?={@open?}
        title={dgettext("cinder", "Edit filters")}
        items={@items}
        list_hook="CinderFilterSortable"
        close_event="toggle_filter_prefs_drawer"
        toggle_event="toggle_filter_visibility"
        reset_event="reset_filter_preferences"
      />
    </div>
    """
  end

  # Every filter can be hidden and dragged — there is no pinned filter — so the
  # drawer's pinned affordances never apply here.
  defp drawer_item(column, prefs) do
    %{
      field: column.field,
      label: column.label,
      checked?: not Cinder.FilterPreferences.hidden?(prefs, column.field),
      disabled?: false,
      reorderable?: true
    }
  end
end
