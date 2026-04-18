module ActiveRecord
  module ConnectionAdapters
    module PostgreSQL
      module Branched
        TABLE_PARAMS = %i[table_name from_table table_1].freeze

        # All SchemaStatements methods whose first parameter is a table name.
        def self.table_methods
          [
            ActiveRecord::ConnectionAdapters::SchemaStatements,
            ActiveRecord::ConnectionAdapters::PostgreSQL::SchemaStatements
          ].flat_map { |mod|
            mod.instance_methods(false).select { |m|
              first_param = mod.instance_method(m).parameters.first
              first_param && TABLE_PARAMS.include?(first_param.last)
            }
          }.uniq
        end

        class Adapter < ActiveRecord::ConnectionAdapters::PostgreSQLAdapter
          ADAPTER_NAME = "PostgreSQL Branched"

          # Methods where the first argument is not the table to shadow,
          # or where shadowing would be wasteful (join table methods pass
          # table_1, not the derived join table name).
          SHADOW_SKIP = %i[create_join_table drop_join_table].freeze

          # Methods with custom shadow handling outside the generic loop.
          SHADOW_HANDLED = %i[rename_table].freeze

          # Intercept everything except SHADOW_SKIP and SHADOW_HANDLED.
          # Shadow#call is idempotent and safe — if the table doesn't
          # exist in public or is already shadowed, it's a no-op.
          SHADOW_BEFORE = Branched.table_methods.-(SHADOW_SKIP).-(SHADOW_HANDLED).freeze

          def initialize(...)
            super
            @branch_manager = BranchManager.new(self, @config)
            @shadow = Shadow.new(self, @branch_manager.branch_schema) unless @branch_manager.primary_branch?
          end

          def configure_connection
            super
            @branch_manager.activate(@shadow)
          end

          SHADOW_BEFORE.each do |method|
            define_method(method) do |table_name, *args, **kwargs, &block|
              @shadow&.call(table_name)
              super(table_name, *args, **kwargs, &block)
            end
          end

          # rename_table needs special handling: the shadow table's sequences
          # live in public, but Rails' rename_table tries to rename them using
          # the branch schema. The table and index renames succeed before the
          # sequence rename fails, so we rescue the sequence error.
          def rename_table(table_name, new_name, **options)
            @shadow&.call(table_name)
            super
          rescue ActiveRecord::StatementInvalid => e
            raise if @branch_manager.primary_branch?
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
