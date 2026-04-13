module ActiveRecord
  module ConnectionAdapters
    module PostgreSQL
      module Branched
        class Adapter < ActiveRecord::ConnectionAdapters::PostgreSQLAdapter
          ADAPTER_NAME = "PostgreSQL Branched"

          SHADOW_BEFORE = %i[
            add_column
            remove_column
            rename_column
            change_column
            change_column_default
            change_column_null
            change_column_comment
            change_table_comment
            add_index
            remove_index
            rename_index
            add_foreign_key
            remove_foreign_key
            add_check_constraint
            remove_check_constraint
            validate_foreign_key
            validate_check_constraint
            drop_table
            change_table
            bulk_change_table
          ].freeze

          def initialize(...)
            super
            @branch_manager = BranchManager.new(self, @config)
            @shadow = Shadow.new(self, @branch_manager.branch_schema)
          end

          def configure_connection
            super
            @branch_manager.activate(@shadow)
          end

          SHADOW_BEFORE.each do |method|
            define_method(method) do |table_name, *args, **kwargs, &block|
              @shadow.call(table_name)
              super(table_name, *args, **kwargs, &block)
            end
          end

          # rename_table needs special handling: the shadow table's sequences
          # live in public, but Rails' rename_table tries to rename them using
          # the branch schema. The table and index renames succeed before the
          # sequence rename fails, so we rescue the sequence error.
          def rename_table(table_name, new_name, **options)
            @shadow.call(table_name)
            super
          rescue ActiveRecord::StatementInvalid => e
            raise unless e.cause.is_a?(PG::UndefinedTable)
          end

          attr_reader :branch_manager
        end
      end
    end
  end
end

ActiveRecord::ConnectionAdapters.register(
  "postgresql_branched",
  "ActiveRecord::ConnectionAdapters::PostgreSQL::Branched::Adapter",
  "activerecord-postgresql-branched"
)
