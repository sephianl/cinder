defmodule Cinder.Theme do
  @moduledoc """
  Theme management for Cinder table components.

  Provides default themes and utilities for merging custom theme configurations.

  ## Basic Usage

      # Using built-in themes
      theme = Cinder.Theme.merge("modern")

      # Using application configuration for default theme
      # config/config.exs
      config :cinder, default_theme: "modern"

  ## Custom Themes

      defmodule MyApp.CustomTheme do
        use Cinder.Theme

        # Table
        set :container_class, "my-custom-table-container"
        set :row_class, "my-custom-row hover:bg-blue-50"

        # Filters
        set :filter_container_class, "my-filter-container"
      end

      # Use in config
      config :cinder, default_theme: MyApp.CustomTheme

      # Or use directly
      theme = Cinder.Theme.merge(MyApp.CustomTheme)

  ## Configuration

  You can set a default theme for all Cinder tables in your application configuration:

      # config/config.exs
      config :cinder, default_theme: "modern"

      # Or use a custom theme module
      config :cinder, default_theme: MyApp.CustomTheme

  Individual tables can still override the configured default:

  ```heex
  <Cinder.collection theme="dark" ...>
    <!-- This table uses "dark" theme, ignoring the configured default -->
  </Cinder.collection>
  ```
  """

  @type theme :: %{atom() => String.t()}

  # All theme properties and their defaults in one place
  @theme_defaults %{
    # Table
    container_class: "",
    controls_class: "",
    table_scroll_class: "",
    table_wrapper_class: "overflow-x-auto",
    table_scroll_rail_class: "",
    table_scroll_thumb_class: "",
    table_class: "w-full border-collapse",
    thead_class: "",
    tbody_class: "",
    header_row_class: "",
    row_class: "",
    th_class: "text-left whitespace-nowrap",
    td_class: "",
    empty_class: "text-center py-4",
    error_container_class: "text-red-600 text-sm",
    error_message_class: "",

    # Filters
    filter_container_class: "",
    filter_header_class: "",
    filter_title_class: "",
    filter_count_class: "",
    filter_clear_all_class: "",
    filter_inputs_class: "",
    filter_input_wrapper_class: "",
    filter_label_class: "",
    filter_clear_button_class: "",
    filter_text_input_class: "",
    filter_date_input_class: "",
    filter_number_input_class:
      "[&::-webkit-outer-spin-button]:appearance-none [&::-webkit-inner-spin-button]:appearance-none [-moz-appearance:textfield]",
    filter_select_input_class: "",
    filter_select_container_class: "",
    filter_select_dropdown_class: "",
    filter_select_option_class: "",
    filter_select_label_class: "",
    filter_select_empty_class: "",
    filter_select_arrow_class: "w-4 h-4 ml-2 flex-shrink-0",
    filter_select_placeholder_class: "text-gray-400",
    filter_radio_group_container_class: "",
    filter_radio_group_option_class: "",
    filter_radio_group_radio_class: "",
    filter_radio_group_label_class: "",
    filter_checkbox_container_class: "",
    filter_checkbox_input_class: "",
    filter_checkbox_label_class: "",
    filter_multiselect_container_class: "",
    filter_multiselect_dropdown_class: "",
    filter_multiselect_option_class: "",
    filter_multiselect_checkbox_class: "",
    filter_multiselect_label_class: "",
    filter_multiselect_empty_class: "",
    filter_multicheckboxes_container_class: "",
    filter_multicheckboxes_option_class: "",
    filter_multicheckboxes_checkbox_class: "",
    filter_multicheckboxes_label_class: "",
    filter_range_container_class: "",
    filter_range_input_group_class: "",
    filter_range_separator_class: "flex items-center px-2 text-sm text-gray-500",
    filter_toggle_class: "cursor-pointer select-none inline-flex items-center gap-1",
    filter_toggle_icon_class: "w-4 h-4",

    # Pagination
    pagination_wrapper_class: "",
    pagination_container_class: "",
    pagination_button_class: "",
    pagination_step_class: "",
    pagination_info_class: "",
    pagination_count_class: "",
    pagination_nav_class: "",
    pagination_current_class: "",
    pagination_ellipsis_class: "",
    page_size_container_class: "",
    page_size_label_class: "",
    page_size_dropdown_class: "",
    page_size_dropdown_container_class: "",
    page_size_option_class: "",
    page_size_selected_class: "",

    # Sorting
    sort_indicator_class: "ml-1 inline-flex items-center align-baseline",
    sort_arrow_wrapper_class: "inline-flex items-center",
    sort_asc_icon_name: "hero-chevron-up",
    sort_asc_icon_class: "w-3 h-3",
    sort_desc_icon_name: "hero-chevron-down",
    sort_desc_icon_class: "w-3 h-3",
    sort_none_icon_name: "hero-chevron-up-down",
    sort_none_icon_class: "w-3 h-3 opacity-50",

    # Loading
    loading_overlay_class: "absolute top-3 right-3 z-30 cinder-loading-indicator",
    loading_row_class: "",
    loading_container_class: "",
    loading_spinner_class: "",
    loading_spinner_circle_class: "",
    loading_spinner_path_class: "",

    # Search
    search_input_class: "w-full px-3 py-2 border rounded",
    search_icon_class: "w-4 h-4",

    # List
    list_container_class: "divide-y divide-gray-200",
    list_item_class: "py-3 px-4 text-gray-900",
    list_item_clickable_class: "cursor-pointer hover:bg-gray-50 transition-colors",
    sort_container_class: "bg-white border border-gray-200 rounded-lg shadow-sm mt-4",
    sort_controls_class: "flex items-center gap-2 p-4",
    sort_controls_label_class: "text-sm text-gray-600 font-medium",
    sort_buttons_class: "flex gap-1",
    sort_button_class: "px-3 py-1 text-sm border rounded transition-colors",
    sort_button_active_class: "bg-blue-50 border-blue-300 text-blue-700",
    sort_button_inactive_class: "bg-white border-gray-300 hover:bg-gray-50",

    # Grid
    grid_container_class: "grid gap-4",
    grid_item_class: "p-4 bg-white border border-gray-200 rounded-lg shadow-sm",
    grid_item_clickable_class: "cursor-pointer hover:shadow-md transition-shadow",

    # Selection
    selection_checkbox_class: "",
    selected_row_class: "bg-blue-50",
    grid_selection_overlay_class: "mb-2",
    selected_item_class: "ring-2 ring-blue-500",
    list_selection_container_class: "mb-2",
    bulk_actions_container_class:
      "p-4 bg-white border border-gray-200 rounded-lg shadow-sm flex gap-2 justify-end",

    # Buttons (used by bulk actions, reusable elsewhere)
    button_class: "px-3 py-1.5 text-sm font-medium rounded",
    button_primary_class: "bg-blue-600 text-white hover:bg-blue-700",
    button_secondary_class: "border border-gray-300 text-gray-700 hover:bg-gray-50",
    button_danger_class: "bg-red-600 text-white hover:bg-red-700",
    button_disabled_class: "opacity-50 cursor-not-allowed",

    # Column preferences (Edit columns drawer)
    column_prefs_container_class: "cinder-column-prefs",
    column_prefs_button_class:
      "inline-flex items-center gap-1 px-3 py-1.5 text-sm border border-gray-200 rounded text-gray-900 hover:bg-gray-50 dark:bg-gray-800 dark:text-white dark:border-gray-700 dark:hover:bg-gray-700",
    column_prefs_button_icon_class: "w-4 h-4",
    column_prefs_header_trigger_class:
      "inline-flex items-center gap-1 cursor-pointer select-none text-gray-900 hover:text-gray-600 dark:text-white dark:hover:text-gray-300",
    column_prefs_backdrop_class:
      "fixed inset-0 z-40 bg-black/30 transition-opacity duration-300 ease-in-out",
    column_prefs_panel_class:
      "fixed top-0 right-0 h-full w-80 max-w-full bg-white text-gray-900 shadow-xl flex flex-col z-50 dark:bg-gray-800 dark:text-white transition-transform duration-300 ease-in-out",
    column_prefs_header_class:
      "flex items-center justify-between px-4 py-3 border-b border-gray-200 dark:border-gray-700",
    column_prefs_title_class: "text-base font-semibold text-gray-900 dark:text-white",
    column_prefs_close_button_class: "p-1 rounded hover:bg-gray-100 dark:hover:bg-gray-700",
    column_prefs_close_icon_class: "w-5 h-5",
    column_prefs_list_class: "flex-1 overflow-y-auto py-2",
    column_prefs_item_class:
      "flex items-center gap-2 px-4 py-2 border-b border-gray-200 last:border-b-0 dark:border-gray-700",
    column_prefs_item_reorderable_class: "cursor-grab",
    column_prefs_item_pinned_class: "opacity-90",
    column_prefs_drag_handle_class: "cinder-drag-handle text-gray-400 dark:text-gray-500",
    column_prefs_drag_handle_icon_class: "w-4 h-4",
    column_prefs_pinned_icon_class: "text-gray-300 w-4 h-4 dark:text-gray-600",
    column_prefs_checkbox_class: "cursor-pointer disabled:cursor-not-allowed",
    column_prefs_label_class: "flex-1 text-sm select-none text-gray-900 dark:text-white",
    column_prefs_footer_class:
      "border-t border-gray-200 px-4 py-3 flex justify-between dark:border-gray-700",
    column_prefs_reset_button_class: "text-sm text-gray-600 hover:underline dark:text-gray-400",
    column_prefs_done_button_class:
      "text-sm font-medium px-3 py-1 rounded bg-blue-600 text-white hover:bg-blue-700 dark:bg-blue-600 dark:hover:bg-blue-700",

    # Filter preferences (Edit filters drawer). The drawer itself reuses the
    # column_prefs_* keys above — one drawer, one styling — so only its trigger,
    # which sits in the filter row rather than the table chrome, has its own.
    filter_prefs_container_class: "cinder-filter-prefs",
    filter_prefs_button_class:
      "inline-flex items-center gap-1 px-3 py-1.5 text-sm border border-gray-200 rounded text-gray-900 hover:bg-gray-50 dark:bg-gray-800 dark:text-white dark:border-gray-700 dark:hover:bg-gray-700",
    filter_prefs_button_icon_class: "w-4 h-4",

    # Filter bar (`show_filters: :bar`). A pill carries `data-active` while its
    # filter holds a value, and a date shortcut `data-chosen` while it is the
    # range the filter holds, for `data-[active]:` / `data-[chosen]:` variants.
    filter_bar_class: "flex flex-wrap items-center gap-2",
    filter_bar_inline_class:
      "flex h-8 items-center gap-2 rounded-full border border-gray-300 bg-white pl-3 pr-0.5 text-sm data-[active]:border-gray-400",
    filter_bar_search_class:
      "flex h-8 w-72 items-center gap-2 rounded-full border border-gray-300 bg-white px-3 text-sm text-gray-900 focus-within:border-blue-500",
    filter_bar_search_input_class:
      "h-full min-w-0 flex-1 border-0 bg-transparent p-0 text-sm placeholder:text-gray-400 focus:ring-0 focus:outline-none",
    filter_bar_pill_class:
      "flex h-8 items-center rounded-full border border-gray-300 bg-white text-sm text-gray-900 data-[active]:border-gray-400",
    filter_bar_pill_button_class:
      "flex h-full items-center gap-1.5 rounded-full px-3 hover:bg-gray-100",
    filter_bar_pill_label_class: "text-gray-500",
    filter_bar_pill_value_class: "max-w-56 truncate font-medium",
    filter_bar_pill_clear_class:
      "flex h-full items-center rounded-r-full pr-2.5 pl-1 text-gray-500 hover:bg-gray-100 hover:text-gray-900",
    filter_bar_icon_class: "h-3.5 w-3.5 shrink-0",
    filter_bar_add_class:
      "flex h-8 items-center gap-1 rounded-full border border-dashed border-gray-300 px-3 text-sm text-gray-500 hover:bg-gray-100",
    filter_bar_menu_class:
      "absolute top-9 left-0 z-40 min-w-48 rounded-lg border border-gray-200 bg-white py-1 shadow-lg",
    filter_bar_menu_item_class:
      "flex w-full items-center justify-between gap-4 px-3 py-1.5 text-left text-sm text-gray-900 hover:bg-gray-100",
    filter_bar_dropdown_class:
      "absolute z-40 min-w-56 max-h-96 overflow-auto rounded-lg border border-gray-200 bg-white p-1 shadow-lg",
    filter_bar_option_class:
      "flex cursor-pointer items-center gap-2 rounded px-2 py-1.5 text-sm text-gray-900 hover:bg-gray-100",
    filter_bar_checkbox_class: "h-4 w-4 rounded border-gray-300",
    filter_bar_shortcuts_class: "grid grid-cols-2 gap-x-1",
    filter_bar_shortcut_class:
      "rounded px-2 py-1.5 text-left text-sm text-gray-900 hover:bg-gray-100 data-[chosen]:bg-gray-100 data-[chosen]:font-medium",
    filter_bar_inputs_class:
      "p-2 [&:not(:first-child)]:mt-1 [&:not(:first-child)]:border-t border-gray-200"
  }

  # Re-export the DSL functionality
  defmacro __using__(opts) do
    quote do
      require Cinder.Theme.DslModule
      Cinder.Theme.DslModule.__using__(unquote(opts))
    end
  end

  @doc """
  Returns the default theme configuration.
  """
  def default do
    complete_default()
    |> apply_theme_property_mapping()
  end

  @doc """
  Returns the given theme or the default theme if nil.

  Used internally by the theme DSL to avoid dialyzer warnings
  when extending themes.
  """
  @spec theme_or_default(map() | nil) :: map()
  def theme_or_default(nil), do: default()
  def theme_or_default(theme) when is_map(theme), do: theme

  @doc """
  Gets the configured default theme from application configuration.

  Returns the theme configured via `config :cinder, default_theme: ...`
  or falls back to "default" if no configuration is set.

  ## Examples

      # With configuration
      Application.put_env(:cinder, :default_theme, "modern")
      Cinder.Theme.get_default_theme()
      #=> returns modern theme configuration

      # Without configuration
      Cinder.Theme.get_default_theme()
      #=> returns "default" theme configuration

  """
  def get_default_theme do
    case Application.get_env(:cinder, :default_theme) do
      nil -> "default"
      theme -> theme
    end
  end

  @doc """
  Merges a theme configuration with the default theme.

  ## Examples

      iex> Cinder.Theme.merge("modern")
      %{container_class: "bg-white shadow-lg rounded-xl border border-gray-100 overflow-hidden", ...}

      iex> Cinder.Theme.merge(MyApp.CustomTheme)
      %{container_class: "custom-container", ...}

  """
  def merge(theme_config)

  def merge("default"),
    do: default() |> apply_theme_property_mapping()

  def merge("modern"),
    do:
      Cinder.Themes.Modern.resolve_theme()
      |> apply_theme_property_mapping()

  def merge("retro"),
    do:
      Cinder.Themes.Retro.resolve_theme()
      |> apply_theme_property_mapping()

  def merge("futuristic"),
    do:
      Cinder.Themes.Futuristic.resolve_theme()
      |> apply_theme_property_mapping()

  def merge("dark"),
    do:
      Cinder.Themes.Dark.resolve_theme()
      |> apply_theme_property_mapping()

  def merge("daisy_ui"),
    do:
      Cinder.Themes.DaisyUI.resolve_theme()
      |> apply_theme_property_mapping()

  def merge("flowbite"),
    do:
      Cinder.Themes.Flowbite.resolve_theme()
      |> apply_theme_property_mapping()

  def merge("compact"),
    do:
      Cinder.Themes.Compact.resolve_theme()
      |> apply_theme_property_mapping()

  def merge(nil),
    do: default() |> apply_theme_property_mapping()

  def merge(theme_module) when is_atom(theme_module) do
    # Check if it's a DSL-based theme module
    try do
      theme_module.resolve_theme()
      |> apply_theme_property_mapping()
    rescue
      _e in UndefinedFunctionError ->
        reraise ArgumentError,
                [message: "Theme module #{theme_module} does not implement resolve_theme/0"],
                __STACKTRACE__
    end
  end

  def merge(theme_name) when is_binary(theme_name) do
    raise ArgumentError,
          "Unknown theme preset: #{theme_name}. Available presets: #{Enum.join(presets(), ", ")}"
  end

  def merge(theme_config) do
    raise ArgumentError,
          "Theme must be a map, string, or theme module, got: #{inspect(theme_config)}"
  end

  @doc """
  Returns a list of available theme presets.
  """
  def presets do
    ["default" | built_in_theme_names()]
  end

  @doc """
  Returns the names of built-in themes that ship with a matching CSS file
  under `priv/themes/`. `"default"` is intentionally excluded — its classes
  live in `theme.ex` itself and don't need a separate `@import`.
  """
  def built_in_theme_names do
    ~w(compact daisy_ui dark flowbite futuristic modern retro)
  end

  @doc """
  Validates a theme configuration.

  Returns :ok if the theme is valid, or {:error, reason} if invalid.
  """
  def validate(theme_module) when is_atom(theme_module) do
    if function_exported?(theme_module, :resolve_theme, 0) do
      # For DSL-based themes, use the DSL validation
      Cinder.Theme.DslModule.validate_theme(theme_module)
    else
      {:error, "Theme module #{theme_module} does not implement resolve_theme/0"}
    end
  end

  def validate(theme_name) when is_binary(theme_name) do
    if theme_name in presets() do
      :ok
    else
      {:error, "Unknown theme preset: #{theme_name}"}
    end
  end

  def validate(_theme_config) do
    {:error, "Theme must be a string or theme module"}
  end

  @doc """
  Gets the complete default theme.
  """
  def complete_default do
    @theme_defaults
  end

  @doc """
  Validates that a theme property key is valid.
  """
  def valid_property?(key) when is_atom(key) do
    Map.has_key?(@theme_defaults, key)
  end

  def valid_property?(_), do: false

  # Applies theme property mapping for backwards compatibility.
  # Currently a no-op since all properties are properly namespaced.
  defp apply_theme_property_mapping(theme), do: theme
end
