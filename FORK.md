# sephianl/cinder

Our fork of [sevenseacat/cinder](https://github.com/sevenseacat/cinder). Keep it as small as
upstream allows: every change here is one we re-apply on each upstream sync.

## Branches and pins

- `main` mirrors `upstream/main`. Never commit to it.
- `main-fork` is `main` plus our changes, starting with this file. It is rebased, not merged,
  so it stays a readable patch stack.
- Apps pin a commit SHA, never the branch:
  - zelo: `backend/core/mix.exs`
  - green: `backend/mix.exs`
- Before rewriting `main-fork`, tag its head (`main-fork-YYYY-MM-DD`) and push the tag, so every
  SHA an app has ever pinned stays fetchable.

## Syncing with upstream

1. `git fetch upstream && git switch main && git merge --ff-only upstream/main`, then push
   `main` (or use GitHub's "Sync fork").
2. Tag the current `main-fork` head and push the tag.
3. `git rebase main main-fork`, and resolve each conflict on its own commit.
4. `MIX_ENV=test mix compile --warnings-as-errors`, `mix test`, and
   `mix gettext.extract --check-up-to-date`.
5. `git push --force-with-lease=main-fork:<old head> origin main-fork`.
6. Bump the pins in zelo and green, and run their LiveView suites.

### Resolving conflicts

- Upstream's structure wins. Port our behaviour onto it rather than restoring ours: selection
  goes through `Cinder.Selection`, URL sync through `Cinder.UrlSync.info_hook/2`, and the filter
  row through upstream's `filter_container` (it carries the partial-input hook).
- Don't hand-merge gettext catalogs. Take either side, run `mix gettext.extract --merge`, then
  put our Dutch translations back. `merge` fuzzy-matches new strings to old ones, so check every
  `fuzzy` entry it adds.
- Upstream's test fixtures are `Music.Album` and `Music.Artist`. Our older tests may still say
  `Cinder.Integration.*`.
- Integration tests that toggle `:disable_async?` can fail once in a full run. Rerun before
  chasing them.
- Some of our CHANGELOG entries sit under upstream's version headings (e.g. v0.16.0). They
  describe this fork, not that upstream release.

## What we carry, and who uses it

| Change | zelo | green | Upstream |
|---|---|---|---|
| Column preferences: hide and reorder columns, trigger, drawer | yes | yes | Declined as a PR (#171); planned for 1.0-beta |
| Filter preferences and the filter-selector row | yes (automatic past 3 filters) | yes | Declined (#220) |
| Default filter values (`default:` on a filter) | yes | | Planned for 1.0-beta (#90) |
| Table state persistence (`persist_state?`), clamping past-the-end pages | | yes | Not planned |
| Filtering on map fields (`Cinder.MapColumn`) | | yes | Not planned |
| `sort_field` / `sort_with` (secondary sort) | yes | | PR open (#251) |
| `select_on_row_click` | yes | | Not planned |
| Select-all in list layouts | yes | | 1.0-beta selects everything matching a query (#202) |
| Masking sensitive columns for session replay (`config :cinder, sensitive_fields:`) | yes | yes | Not planned |
| Column slots kept out of the async load task (it copied the host LiveView's assigns per column) | yes | yes | PR open (#250) |
| JS hooks entry `createCinderHooks` (column and filter preferences, persistence) | yes | yes | Upstream uses colocated hooks; ours sits beside them |

### Deliberate differences in look

Kept on purpose; upstream offers no way to configure them.

- Pagination: "Showing 1–10 of 50 items", Previous/Next text buttons, page size on the left
  in a drop-up.
- "Reset filters" instead of "Clear all", rendered as its own control.
- A theme class for rows while loading, instead of a hard-coded `opacity-75`.

## Upstream direction

1.0-beta replaces Cinder's component layer and keeps the query engine (see upstream issue #249).
PRs touching the LiveComponent, renderers or themes are declined until then. Query-engine fixes
are welcome. After 1.0, check which of the rows above upstream now covers, and drop ours.
