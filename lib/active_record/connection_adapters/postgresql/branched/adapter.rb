module ActiveRecord
  module ConnectionAdapters
    module PostgreSQL
      module Branched
        # All SchemaStatements methods whose first parameter name
        # contains "table" — covers table_name, from_table, table_1,
        # table_names, and any future variant.
        def self.table_methods
          [
            ActiveRecord::ConnectionAdapters::SchemaStatements,
            ActiveRecord::ConnectionAdapters::PostgreSQL::SchemaStatements
          ].flat_map { |mod|
            mod.instance_methods(false).select { |m|
              first_param = mod.instance_method(m).parameters.first
              first_param && first_param.last.to_s.include?("table")
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

          # Everything else with a table param gets the generic wrapper.
          # Shadow#call is idempotent — if the table doesn't exist in
          # public or is already shadowed, it's a no-op.
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
            define_method(method) do |*args, **kwargs, &block|
              @shadow&.call(args.first)
              super(*args, **kwargs, &block)
            end
          end

          # drop_table takes *table_names (splat) in Rails 8.1+.
          # For tables from public: shadow first (so the branch copy
          # exists for DROP to resolve to), then super drops the branch
          # copy, then create a tombstone in the dropped schema to block
          # search_path fallthrough.
          def drop_table(*table_names, **options)
            if @branch_manager.primary_branch?
              super
            else
              table_names.each { |t| @shadow&.call(t) }
              super
              table_names.each { |t| @shadow&.drop_table(t) }
            end
          end

          # create_table after drop_table should work — remove the
          # tombstone so the new table takes precedence.
          def create_table(*args, **kwargs, &block)
            @shadow&.undrop_table(args.first)
            super
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

          attr_reader :branch_manager, :shadow
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
