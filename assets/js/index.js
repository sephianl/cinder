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
 * `CinderTableScroll` is only attached when the theme sets
 * `table_scroll_rail_class`; see `createTableScrollHook`.
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

// A thumb narrower than this is too small to grab, however wide the table.
const THUMB_FLOOR = 32;

/**
 * What a table wider than its container needs to show it can be scrolled
 * sideways: a horizontal scrollbar that sticks to the bottom of the viewport,
 * and flags for the theme to draw a shadow on each side that has more to show.
 *
 * The native bar sits at the end of the scrolling element, which on a long
 * table is below the fold; this hook hides it and drives the same element from
 * a rail of its own. The rail is drawn rather than delegated to a second
 * scrolling element, because the two would have to keep each other's
 * `scrollLeft` in step and would bounce the event back and forth doing it.
 *
 * The markup it expects, all within the hook element: `[data-scroll-body]` (the
 * element that overflows), `[data-scroll-rail]` (the track) and
 * `[data-scroll-thumb]` inside it. While the body overflows, the rail loses its
 * `hidden` attribute and the body gains `data-scroll-proxied`, for the app's CSS
 * to hide the native bar by. The hook element carries `data-hidden-left` and
 * `data-hidden-right` while columns sit out of view on that side.
 */
function createTableScrollHook() {
  return {
    mounted() {
      this.body = this.el.querySelector("[data-scroll-body]");
      this.rail = this.el.querySelector("[data-scroll-rail]");
      this.thumb = this.el.querySelector("[data-scroll-thumb]");
      this.onScroll = () => this.position();
      this.body.addEventListener("scroll", this.onScroll, { passive: true });

      this.onDown = (e) => this.grab(e);
      this.onMove = (e) => this.drag(e);
      this.onUp = () => this.release();
      this.rail.addEventListener("pointerdown", this.onDown);
      this.rail.addEventListener("pointermove", this.onMove);
      this.rail.addEventListener("pointerup", this.onUp);
      this.rail.addEventListener("pointercancel", this.onUp);

      // The table's width moves with the viewport and with a late font, neither
      // of which is a re-render.
      this.observer = new ResizeObserver(() => this.measure());
      this.observe();
    },

    // A re-render can change the width, and puts back what this hook set: the
    // server renders the rail hidden.
    updated() {
      this.observe();
    },

    destroyed() {
      this.observer.disconnect();
      this.body.removeEventListener("scroll", this.onScroll);
      this.rail.removeEventListener("pointerdown", this.onDown);
      this.rail.removeEventListener("pointermove", this.onMove);
      this.rail.removeEventListener("pointerup", this.onUp);
      this.rail.removeEventListener("pointercancel", this.onUp);
    },

    observe() {
      this.observer.disconnect();
      this.observer.observe(this.body);
      // The table itself can change size without the container around it
      // changing at all.
      if (this.body.firstElementChild) {
        this.observer.observe(this.body.firstElementChild);
      }
      this.measure();
    },

    measure() {
      const scrollable = this.body.scrollWidth > this.body.clientWidth + 1;
      this.rail.hidden = !scrollable;
      this.body.toggleAttribute("data-scroll-proxied", scrollable);

      if (scrollable) {
        const share = this.body.clientWidth / this.body.scrollWidth;
        this.thumbWidth = Math.max(this.rail.clientWidth * share, THUMB_FLOOR);
        this.thumb.style.width = `${this.thumbWidth}px`;
      }
      this.position();
    },

    position() {
      const overflow = this.overflow();
      const x =
        overflow > 0 ? (this.body.scrollLeft / overflow) * this.travel() : 0;

      this.thumb.style.transform = `translateX(${x}px)`;
      this.el.toggleAttribute("data-hidden-left", this.body.scrollLeft > 1);
      this.el.toggleAttribute(
        "data-hidden-right",
        this.body.scrollLeft < overflow - 1,
      );
    },

    grab(e) {
      const thumb = this.thumb.getBoundingClientRect();
      const onThumb = e.clientX >= thumb.left && e.clientX <= thumb.right;
      // Grabbing the track rather than the thumb jumps to the click, thumb
      // centred, and carries on as a drag from there.
      this.offset = onThumb ? e.clientX - thumb.left : this.thumbWidth / 2;
      this.rail.setPointerCapture(e.pointerId);
      this.rail.toggleAttribute("data-dragging", true);
      this.drag(e);
    },

    drag(e) {
      if (!this.rail.hasAttribute("data-dragging")) return;
      e.preventDefault();

      const x =
        e.clientX - this.rail.getBoundingClientRect().left - this.offset;
      const travel = this.travel();
      const ratio = travel > 0 ? Math.min(Math.max(x / travel, 0), 1) : 0;

      this.body.scrollLeft = ratio * this.overflow();
    },

    release() {
      this.rail.toggleAttribute("data-dragging", false);
    },

    // How far the thumb may move, and how far the table may scroll. The thumb
    // floor eats into the first, so the two only agree through this ratio.
    travel() {
      return this.rail.clientWidth - this.thumbWidth;
    },

    overflow() {
      return this.body.scrollWidth - this.body.clientWidth;
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
    CinderTableScroll: createTableScrollHook(),
  };
}

export default createCinderHooks;
