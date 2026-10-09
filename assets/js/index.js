/**
 * Cinder LiveView hooks.
 *
 *   import { createCinderHooks } from "cinder"
 *   import Sortable from "sortablejs" // optional — needed for drag-to-reorder
 *
 *   const liveSocket = new LiveSocket("/live", Socket, {
 *     hooks: { ...createCinderHooks({ Sortable }) }
 *   })
 *
 * Without `sortablejs`, show/hide and persistence still work; only
 * drag-to-reorder is disabled.
 */

const COLUMN_STORAGE_PREFIX = "cinder:column_prefs:";
const FILTER_STORAGE_PREFIX = "cinder:filter_prefs:";

/**
 * Per-table localStorage I/O for one preference editor. Columns and filters
 * each get their own prefix, event and storage entry, so trimming the filter
 * row never disturbs which columns the table shows.
 */
function createPrefsHook({ prefix, changedEvent, applyEvent, label }) {
  return {
    mounted() {
      this.tableId = this.el.dataset.cinderTableId;
      this.storageKey = prefix + this.tableId;

      this.handleEvent(changedEvent, (payload) => {
        if (!payload || payload.id !== this.tableId) return;
        this.writePrefs({ order: payload.order, hidden: payload.hidden });
      });

      const stored = this.readPrefs() || {};
      this.pushEventTo(this.el, applyEvent, stored);
    },

    readPrefs() {
      try {
        const raw = window.localStorage.getItem(this.storageKey);
        return raw ? JSON.parse(raw) : null;
      } catch (e) {
        console.warn(`[cinder] failed to read ${label} prefs`, e);
        return null;
      }
    },

    writePrefs(prefs) {
      try {
        window.localStorage.setItem(this.storageKey, JSON.stringify(prefs));
      } catch (e) {
        console.warn(`[cinder] failed to persist ${label} prefs`, e);
      }
    },
  };
}

/** SortableJS binding on a prefs drawer's list. No-op without Sortable. */
function createPrefsSortableHook(Sortable, reorderEvent) {
  return {
    mounted() {
      if (!Sortable) return;
      this.sortable = Sortable.create(this.el, this.sortableOptions());
    },

    updated() {
      if (Sortable && !this.sortable) {
        this.sortable = Sortable.create(this.el, this.sortableOptions());
      }
    },

    sortableOptions() {
      return {
        animation: 150,
        filter: '[data-reorderable="false"], input',
        preventOnFilter: false,
        onEnd: () => this.pushOrder(),
      };
    },

    destroyed() {
      if (this.sortable) {
        this.sortable.destroy();
        this.sortable = null;
      }
    },

    pushOrder() {
      const order = Array.from(this.el.children)
        .filter((el) => el.dataset.reorderable !== "false")
        .map((el) => el.dataset.field)
        .filter(Boolean);

      this.pushEventTo(this.el, reorderEvent, { order });
    },
  };
}

/** Pass `{ Sortable }` to enable drag-to-reorder. */
export function createCinderHooks({ Sortable } = {}) {
  return {
    CinderColumnPrefs: createPrefsHook({
      prefix: COLUMN_STORAGE_PREFIX,
      changedEvent: "cinder:column_prefs_changed",
      applyEvent: "apply_column_preferences",
      label: "column",
    }),
    CinderColumnSortable: createPrefsSortableHook(Sortable, "reorder_columns"),
    CinderFilterPrefs: createPrefsHook({
      prefix: FILTER_STORAGE_PREFIX,
      changedEvent: "cinder:filter_prefs_changed",
      applyEvent: "apply_filter_preferences",
      label: "filter",
    }),
    CinderFilterSortable: createPrefsSortableHook(Sortable, "reorder_filters"),
  };
}

export default createCinderHooks;
