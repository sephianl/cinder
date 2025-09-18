defmodule Cinder.Table.ColumnsWithFiltersSortingTest do
  @moduledoc """
  Tests that columns with filters preserve their sorting capability.
  This test directly tests the component rendering without LiveView.
  """
  use ExUnit.Case, async: true
  import Phoenix.Component, only: [sigil_H: 2]

  # Test resource
  defmodule TestProduct do
    use Ash.Resource,
      domain: nil,
      data_layer: Ash.DataLayer.Ets,
      validate_domain_inclusion?: false

    ets do
      private?(true)
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:name, :string)
      attribute(:price, :decimal)
      attribute(:status, :string)
      attribute(:created_at, :utc_datetime)
    end

    actions do
      defaults([:create, :read])
    end
  end

  defmodule TestDomain do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource(TestProduct)
    end
  end

  describe "columns with filters maintain sortability" do
    test "process_columns preserves sortable state for columns with filters" do
      # Define columns with various filter configurations
      col_slots = [
        %{
          field: "name",
          sort: true,
          filter: true,  # Simple filter
          inner_block: fn -> "Name" end,
          __slot__: :col
        },
        %{
          field: "price",
          sort: true,
          filter: [type: :number_range],  # Complex filter
          inner_block: fn -> "Price" end,
          __slot__: :col
        },
        %{
          field: "status",
          sort: false,  # Explicitly not sortable
          filter: [type: :select, options: ["active", "inactive"]],
          inner_block: fn -> "Status" end,
          __slot__: :col
        },
        %{
          field: "created_at",
          sort: true,
          filter: false,  # No filter, just sortable
          inner_block: fn -> "Created At" end,
          __slot__: :col
        }
      ]

      # Process the columns
      processed = Cinder.Table.process_columns(col_slots, TestProduct)

      # Verify sortable states are preserved
      name_col = Enum.find(processed, &(&1.field == "name"))
      assert name_col.sortable == true, "Name column should be sortable despite having a filter"

      price_col = Enum.find(processed, &(&1.field == "price"))
      assert price_col.sortable == true, "Price column should be sortable despite having a number range filter"

      status_col = Enum.find(processed, &(&1.field == "status"))
      assert status_col.sortable == false, "Status column should not be sortable as explicitly set"

      created_at_col = Enum.find(processed, &(&1.field == "created_at"))
      assert created_at_col.sortable == true, "Created at column should be sortable"
    end

    test "merge_filter_configurations preserves sortable state" do
      # Simulate processed columns with filters
      processed_columns = [
        %{
          field: "name",
          label: "Name",
          sortable: true,
          filterable: true,
          filter_type: :text,
          __slot__: :col
        },
        %{
          field: "price",
          label: "Price",
          sortable: true,
          filterable: true,
          filter_type: :number_range,
          __slot__: :col
        },
        %{
          field: "status",
          label: "Status",
          sortable: false,
          filterable: true,
          filter_type: :select,
          __slot__: :col
        },
        %{
          field: "created_at",
          label: "Created At",
          sortable: true,
          filterable: false,
          __slot__: :col
        }
      ]

      # Simulate filter-only slots
      filter_slots = [
        %{
          field: "department",
          label: "Department",
          sortable: false,
          filterable: true,
          filter_type: :select,
          __slot__: :filter
        }
      ]

      # Merge configurations
      merged = Cinder.Table.merge_filter_configurations(processed_columns, filter_slots)

      # Should include filterable columns plus filter slots
      assert length(merged) == 4  # 3 filterable columns + 1 filter slot

      # Check that sortable states are preserved in merged result
      name_config = Enum.find(merged, &(&1.field == "name"))
      assert name_config.sortable == true

      price_config = Enum.find(merged, &(&1.field == "price"))
      assert price_config.sortable == true

      status_config = Enum.find(merged, &(&1.field == "status"))
      assert status_config.sortable == false

      dept_config = Enum.find(merged, &(&1.field == "department"))
      assert dept_config.sortable == false
    end

    test "conversion to legacy format preserves sortable based on slot type" do
      alias Cinder.Table.LiveComponent

      # Test regular column with filter
      col_with_filter = %{
        field: "name",
        label: "Name",
        sortable: true,
        filterable: true,
        filter_type: :text,
        __slot__: :col
      }

      converted_col = LiveComponent.convert_filter_config_to_legacy_format(col_with_filter)
      assert converted_col.sortable == true, "Column with filter should preserve sortable=true"

      # Test filter-only slot
      filter_slot = %{
        field: "department",
        label: "Department",
        sortable: false,
        filterable: true,
        filter_type: :select,
        __slot__: :filter
      }

      converted_filter = LiveComponent.convert_filter_config_to_legacy_format(filter_slot)
      assert converted_filter.sortable == false, "Filter slot should remain non-sortable"

      # Test column without explicit sortable (should default based on slot type)
      col_no_explicit = %{
        field: "price",
        label: "Price",
        filterable: true,
        filter_type: :number_range,
        __slot__: :col
        # No sortable key
      }

      converted_default = LiveComponent.convert_filter_config_to_legacy_format(col_no_explicit)
      assert converted_default.sortable == true, "Column should default to sortable=true"
    end
  end

end