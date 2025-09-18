defmodule Cinder.Table.SortingWithFiltersTest do
  use ExUnit.Case
  alias Cinder.Table.LiveComponent

  describe "sorting with filtered columns" do
    test "columns with filters preserve their sortable state" do
      # Test data simulating processed columns with filters
      processed_columns = [
        %{
          field: "name",
          label: "Name",
          sortable: true,
          filterable: true,
          filter_type: :text,
          filter_options: [],
          __slot__: :col
        },
        %{
          field: "status",
          label: "Status",
          sortable: false,  # Explicitly not sortable
          filterable: true,
          filter_type: :select,
          filter_options: [options: ["active", "inactive"]],
          __slot__: :col
        },
        %{
          field: "created_at",
          label: "Created At",
          sortable: true,
          filterable: false,  # Not filterable but sortable
          __slot__: :col
        }
      ]

      # Test the conversion function
      converted = Enum.map(processed_columns, &LiveComponent.convert_filter_config_to_legacy_format/1)

      # Verify sortable states are preserved
      name_col = Enum.find(converted, &(&1.field == "name"))
      assert name_col.sortable == true, "Name column should remain sortable"

      status_col = Enum.find(converted, &(&1.field == "status"))
      assert status_col.sortable == false, "Status column should remain not sortable"

      created_at_col = Enum.find(converted, &(&1.field == "created_at"))
      assert created_at_col.sortable == true, "Created at column should remain sortable"
    end

    test "filter-only slots are never sortable" do
      # Test data for filter-only slots
      filter_slots = [
        %{
          field: "department",
          label: "Department",
          sortable: false,  # Filter slots are always non-sortable
          filterable: true,
          filter_type: :select,
          filter_options: [options: ["Sales", "Marketing"]],
          __slot__: :filter
        },
        %{
          field: "date_range",
          label: "Date Range",
          sortable: false,
          filterable: true,
          filter_type: :date_range,
          filter_options: [],
          __slot__: :filter
        }
      ]

      # Test the conversion function
      converted = Enum.map(filter_slots, &LiveComponent.convert_filter_config_to_legacy_format/1)

      # Verify filter slots are not sortable
      dept_filter = Enum.find(converted, &(&1.field == "department"))
      assert dept_filter.sortable == false, "Department filter should not be sortable"

      date_filter = Enum.find(converted, &(&1.field == "date_range"))
      assert date_filter.sortable == false, "Date range filter should not be sortable"
    end

    test "default sortable behavior based on slot type" do
      # Test configs without explicit sortable value
      configs = [
        %{
          field: "regular_col",
          label: "Regular Column",
          filterable: true,
          __slot__: :col
          # No sortable key - should default to true for columns
        },
        %{
          field: "filter_only",
          label: "Filter Only",
          filterable: true,
          __slot__: :filter
          # No sortable key - should default to false for filters
        }
      ]

      converted = Enum.map(configs, &LiveComponent.convert_filter_config_to_legacy_format/1)

      regular_col = Enum.find(converted, &(&1.field == "regular_col"))
      assert regular_col.sortable == true, "Regular column should default to sortable"

      filter_only = Enum.find(converted, &(&1.field == "filter_only"))
      assert filter_only.sortable == false, "Filter slot should default to not sortable"
    end

    test "explicitly set sortable values are respected" do
      # Test that explicit sortable values override defaults
      configs = [
        %{
          field: "explicitly_sortable",
          label: "Explicitly Sortable",
          sortable: true,  # Explicitly set
          filterable: true,
          __slot__: :col
        },
        %{
          field: "explicitly_not_sortable",
          label: "Explicitly Not Sortable",
          sortable: false,  # Explicitly set
          filterable: true,
          __slot__: :col
        }
      ]

      converted = Enum.map(configs, &LiveComponent.convert_filter_config_to_legacy_format/1)

      sortable_col = Enum.find(converted, &(&1.field == "explicitly_sortable"))
      assert sortable_col.sortable == true, "Explicitly sortable column should be sortable"

      not_sortable_col = Enum.find(converted, &(&1.field == "explicitly_not_sortable"))
      assert not_sortable_col.sortable == false, "Explicitly non-sortable column should not be sortable"
    end
  end
end