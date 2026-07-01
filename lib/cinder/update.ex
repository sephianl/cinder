defmodule Cinder.Update do
  @moduledoc """
  Efficient in-memory updates for Cinder collection data.

  This module provides functions to update individual items in a collection's
  data without triggering a full database re-query. This is useful for applying
  small changes received via PubSub (e.g., status changes, counter increments)
  where re-fetching all 25+ items would be wasteful.

  ## Usage

      # Update a single item by ID
      def handle_info({:user_status_changed, user_id, new_status}, socket) do
        {:noreply, update_item(socket, "users-table", user_id, fn user ->
          %{user | status: new_status}
        end)}
      end

      # Update multiple items with the same function
      def handle_info({:users_activated, user_ids}, socket) do
        {:noreply, update_items(socket, "users-table", user_ids, fn user ->
          %{user | active: true}
        end)}
      end

      # Only update if the item is currently visible (no-op otherwise)
      def handle_info({:user_updated, user_id, changes}, socket) do
        {:noreply, update_if_visible(socket, "users-table", user_id, fn user ->
          Map.merge(user, changes)
        end)}
      end

  ## Caveats

  - These functions modify in-memory data only. Computed fields, aggregates,
    and calculations that come from the database will NOT be recalculated.
  - For changes that affect derived data, use `refresh_table/2` instead.
  - If the item is not found in the current data, the update is silently ignored.
  - The `update_if_visible` functions check visibility within the component itself.
  """

  import Phoenix.LiveView, only: [send_update: 2]

  @doc """
  Updates a single item in a collection by its ID.

  Applies the given function to the item matching the ID. If no item matches,
  the data remains unchanged.

  ## Parameters

  - `socket` - The LiveView socket
  - `collection_id` - The ID of the collection (string)
  - `id` - The ID of the item to update
  - `update_fn` - A function that receives the item and returns the updated item

  ## Returns

  The socket (unchanged, but update message has been sent).

  ## Examples

      # Update user's online status
      update_item(socket, "users-table", user_id, fn user ->
        %{user | online: true}
      end)

      # Increment a counter
      update_item(socket, "posts-table", post_id, fn post ->
        %{post | view_count: post.view_count + 1}
      end)
  """
  def update_item(socket, collection_id, id, update_fn)
      when is_binary(collection_id) and is_function(update_fn, 1) do
    send_update(Cinder.LiveComponent,
      id: collection_id,
      __update_item__: {id, update_fn}
    )

    socket
  end

  @doc """
  Updates multiple items in a collection by their IDs.

  Applies the given function to all items whose IDs are in the provided list.
  Items not in the list are left unchanged.

  ## Parameters

  - `socket` - The LiveView socket
  - `collection_id` - The ID of the collection (string)
  - `ids` - List of IDs of items to update
  - `update_fn` - A function that receives each item and returns the updated item

  ## Returns

  The socket (unchanged, but update message has been sent).

  ## Examples

      # Mark multiple users as active
      update_items(socket, "users-table", user_ids, fn user ->
        %{user | active: true}
      end)

      # Apply discount to selected products
      update_items(socket, "products-table", product_ids, fn product ->
        %{product | price: product.price * 0.9}
      end)
  """
  def update_items(socket, collection_id, ids, update_fn)
      when is_binary(collection_id) and is_list(ids) and is_function(update_fn, 1) do
    send_update(Cinder.LiveComponent,
      id: collection_id,
      __update_items__: {ids, update_fn}
    )

    socket
  end

  @doc """
  Updates an item only if it's currently visible in the collection.

  This combines the efficiency of `update_item/4` with visibility checking.
  The component itself checks if the item exists in its current data before
  applying the update. If the item is not visible, the update function is never
  called, enabling lazy loading patterns.

  You can pass either an ID or a raw item (struct/map with the ID field). When
  passing a raw item, that item is passed to your update function instead of
  the existing table data - useful for lazy loading scenarios where you want
  to transform incoming PubSub data.

  Safe to call when you're unsure if the item is currently displayed.

  ## Parameters

  - `socket` - The LiveView socket
  - `collection_id` - The ID of the collection (string)
  - `id_or_item` - The ID of the item to update, or a raw item (map/struct with ID field)
  - `update_fn` - A function that receives the item and returns the updated item

  ## Returns

  The socket (unchanged, but update message has been sent to component).

  ## Examples

      # Simple update - pass ID, receive existing item from table
      def handle_info({:user_typing, user_id}, socket) do
        {:noreply, update_if_visible(socket, "users-table", user_id, fn user ->
          %{user | typing: true}
        end)}
      end

      # Lazy loading - pass raw item, receive it back for transformation
      def handle_info({:user_updated, raw_user}, socket) do
        {:noreply, update_if_visible(socket, "users-table", raw_user, fn raw ->
          {:ok, loaded} = Ash.load(raw, [:profile, :settings])
          loaded
        end)}
      end
  """
  def update_if_visible(socket, collection_id, id, update_fn)
      when is_binary(collection_id) and is_function(update_fn, 1) do
    send_update(Cinder.LiveComponent,
      id: collection_id,
      __update_item_if_visible__: {id, update_fn}
    )

    socket
  end

  @doc """
  Updates multiple items only if any are currently visible.

  Like `update_if_visible/4` but for multiple IDs. Only items that are both
  in the provided list AND currently visible will be updated. The component
  itself determines which items are visible by checking its current data.

  The update function is called ONCE with ALL visible items, enabling efficient
  batch operations. If no items are visible, the function is never called.

  Also accepts a single struct for convenience - it will be wrapped in a list.

  ## Parameters

  - `socket` - The LiveView socket
  - `collection_id` - The ID of the collection (string)
  - `ids_or_items` - List of IDs, list of raw items, or a single struct
  - `update_fn` - A function that receives a list of visible items and returns
    either a list of updated items or a map of `%{id => updated_item}`

  ## Returns

  The socket (unchanged, but update message has been sent to component).

  ## Examples

      # Simple batch update
      def handle_info({:users_went_offline, user_ids}, socket) do
        {:noreply, update_items_if_visible(socket, "users-table", user_ids, fn users ->
          Enum.map(users, &%{&1 | online: false})
        end)}
      end

      # Lazy batch loading - only loads visible items
      def handle_info(%{payload: %{data: data}}, socket) do
        items = List.wrap(data)
        ids = Enum.map(items, & &1.id)
        raw_by_id = Map.new(items, &{&1.id, &1})

        {:noreply, update_items_if_visible(socket, "table", ids, fn visible_items ->
          to_load = Enum.map(visible_items, &raw_by_id[&1.id])
          {:ok, loaded} = Ash.load(to_load, [:relations], opts)
          loaded
        end)}
      end
  """
  def update_items_if_visible(socket, collection_id, item, update_fn)
      when is_binary(collection_id) and is_struct(item) and is_function(update_fn, 1) do
    update_items_if_visible(socket, collection_id, [item], update_fn)
  end

  def update_items_if_visible(socket, collection_id, ids, update_fn)
      when is_binary(collection_id) and is_list(ids) and is_function(update_fn, 1) do
    send_update(Cinder.LiveComponent,
      id: collection_id,
      __update_items_if_visible__: {ids, update_fn}
    )

    socket
  end

  @doc """
  Upserts items into a collection: rows already present (matched by the id field)
  are replaced in place, rows not yet present are appended.

  Unlike `update_items_if_visible/4`, this DOES add rows that are not currently
  visible. It is the in-place equivalent of a refresh for newly-created records:
  the caller loads the row exactly as the table needs it (same loads as the
  collection query) and hands it over, avoiding a full re-query.

  `update_fn` is applied to every provided item (both the updated and the newly
  inserted ones) before it lands in the data list. Pass the identity when the
  items are already render-ready.

  Inserted rows are appended in the order given; call `Cinder.Refresh.refresh_table/2`
  when you need authoritative sort/pagination.

  Also accepts a single struct for convenience.

  ## Examples

      # A newly-created record streamed in via PubSub, loaded as the table needs it
      def handle_info(%{topic: "route:created:" <> _, payload: %{data: data}}, socket) do
        {:ok, routes} = Ash.load(List.wrap(data), @route_loads, lazy?: true)
        {:noreply, Cinder.upsert_items(socket, "routes-table", routes)}
      end
  """
  def upsert_items(socket, collection_id, item, update_fn \\ &Function.identity/1)

  def upsert_items(socket, collection_id, item, update_fn)
      when is_binary(collection_id) and is_struct(item) and is_function(update_fn, 1) do
    upsert_items(socket, collection_id, [item], update_fn)
  end

  def upsert_items(socket, collection_id, items, update_fn)
      when is_binary(collection_id) and is_list(items) and is_function(update_fn, 1) do
    send_update(Cinder.LiveComponent,
      id: collection_id,
      __upsert_items__: {items, update_fn}
    )

    socket
  end

  @doc """
  Removes rows from a collection by their IDs.

  Filters the matching rows out of the collection's in-memory data without
  triggering a database re-query. This is the in-place counterpart to
  `upsert_items/4` for rows that were injected client-side (e.g. transient
  ghost/preview rows) and need to disappear without a full `refresh_table/2`
  round-trip — which would re-query asynchronously and race any subsequent
  in-memory writes.

  IDs not currently present are silently ignored.

  Also accepts a single ID for convenience.

  ## Examples

      # Drop transient preview rows that no longer apply
      Cinder.remove_items(socket, "routes-table", stale_candidate_ids)
  """
  def remove_items(socket, collection_id, ids)
      when is_binary(collection_id) and is_list(ids) do
    send_update(Cinder.LiveComponent,
      id: collection_id,
      __remove_items__: ids
    )

    socket
  end

  def remove_items(socket, collection_id, id) when is_binary(collection_id) do
    remove_items(socket, collection_id, [id])
  end
end
