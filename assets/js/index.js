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
 *
 * Everything these hooks keep in the browser is namespaced by
 * `data-cinder-storage-scope` on <html>. Stamp it with the signed-in user's id:
 *
 *   <html data-cinder-storage-scope={@current_user && @current_user.id}>
 *
 * Without it every visitor shares one bucket, which is right for a table behind
 * no login and wrong for a workstation two people take turns at.
 */

const COLUMN_STORAGE_PREFIX = "cinder:column_prefs:";
const FILTER_STORAGE_PREFIX = "cinder:filter_prefs:";
const STATE_DURABLE_PREFIX = "cinder:table_durable:";
const STATE_SESSION_PREFIX = "cinder:table_session:";

/**
 * Everything a table stores is scoped to one user, so two people sharing a
 * browser profile do not inherit each other's layout or filters. The host app
 * stamps `data-cinder-storage-scope` on <html>; without it every visitor shares
 * the "anon" bucket, which is the right behaviour for a table behind no login.
 */
function storageScope() {
  try {
    return document.documentElement.dataset.cinderStorageScope || "anon";
  } catch (e) {
    return "anon";
  }
}

/**
 * Resolving the store can itself throw, not just reading from it — a browser set
 * to block site data, or a thumbnailer. A null store makes every read empty and
 * every write a no-op, which is the same path as a browser that has never
 * stored anything.
 */
function resolveStore(kind) {
  try {
    return kind === "durable" ? window.localStorage : window.sessionStorage;
  } catch (e) {
    return null;
  }
}

function readStore(kind, key) {
  const store = resolveStore(kind);
  if (!store) return null;

  try {
    const raw = store.getItem(key);
    return raw ? JSON.parse(raw) : null;
  } catch (e) {
    console.warn(`[cinder] failed to read ${kind} table state`, e);
    return null;
  }
}

function writeStore(kind, key, payload) {
  const store = resolveStore(kind);
  if (!store) return;

  try {
    store.setItem(key, JSON.stringify(payload));
  } catch (e) {
    console.warn(`[cinder] failed to persist ${kind} table state`, e);
  }
}

/**
 * Per-table localStorage I/O for one preference editor. Columns and filters
 * each get their own prefix, event and storage entry, so trimming the filter
 * row never disturbs which columns the table shows.
 */
function createPrefsHook({ prefix, changedEvent, applyEvent, label }) {
  return {
    mounted() {
      this.tableId = this.el.dataset.cinderTableId;
      this.storageKey = prefix + storageScope() + ":" + this.tableId;

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

/**
 * Remembers a table's state between visits, split across two stores by whether
 * the state hides rows.
 *
 * Sort and page size go to localStorage: they reorder rather than subtract, a
 * stale value is visible in the column header, and undoing it costs one click.
 * Filter values and the search term go to sessionStorage: they subtract rows,
 * and a stale one is invisible in its effect, so they die with the tab.
 *
 * The server decides what belongs where (`Cinder.StateStorage`) and sends both
 * payloads already split; this hook only moves them in and out of the browser.
 * It pushes what it found on mount, which is what releases the table's
 * hydration gate — so it must push even when it found nothing.
 */
function createTableStateHook() {
  return {
    mounted() {
      this.tableId = this.el.dataset.cinderTableId;
      const scope = storageScope();
      this.keys = {
        durable: STATE_DURABLE_PREFIX + scope + ":" + this.tableId,
        session: STATE_SESSION_PREFIX + scope + ":" + this.tableId,
      };

      this.handleEvent("cinder:table_state_changed", (payload) => {
        if (!payload || payload.id !== this.tableId) return;
        writeStore("durable", this.keys.durable, payload.durable);
        writeStore("session", this.keys.session, payload.session);
      });

      this.pushEventTo(this.el, "hydrate_table_state", {
        durable: readStore("durable", this.keys.durable),
        session: readStore("session", this.keys.session),
      });
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
    CinderTableState: createTableStateHook(),
  };
}

export default createCinderHooks;
