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
            drop_table
            rename_table
            change_table
            bulk_change_table
          ].freeze

          def configure_connection
            super
            @branch_manager = BranchManager.new(self, @config)
            @branch_manager.activate
          end

          SHADOW_BEFORE.each do |method|
            define_method(method) do |table_name, *args, **kwargs, &block|
              shadow.call(table_name)
              super(table_name, *args, **kwargs, &block)
            end
          end

          attr_reader :branch_manager

          private

          def shadow
            Shadow.new(self, @branch_manager)
          end
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
