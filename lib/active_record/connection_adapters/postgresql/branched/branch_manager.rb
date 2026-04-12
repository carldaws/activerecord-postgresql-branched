module ActiveRecord
  module ConnectionAdapters
    module PostgreSQL
      module Branched
        class BranchManager
          attr_reader :branch, :schema

          def initialize(connection, config = nil)
            @connection = connection
            @config = config || connection.instance_variable_get(:@config) || {}
            @branch = resolve_branch
            @schema = sanitise(@branch)
          end

          def activate
            return if primary_branch?

            ensure_schema
            set_search_path
            shadow_migration_tables
          end

          def primary_branch?
            @branch == primary_branch_name
          end

          def primary_branch_name
            (@config[:primary_branch] || "main").to_s
          end

          def self.sanitise(branch)
            "branch_" + branch.downcase.gsub(/[\/\-\.]/, "_").gsub(/[^a-z0-9_]/, "")
          end

          private

          def resolve_branch
            @config[:branch_override]&.to_s ||
              ENV["PGBRANCH"] ||
              `git branch --show-current`.strip
          end

          def sanitise(branch)
            self.class.sanitise(branch)
          end

          def ensure_schema
            @connection.execute("CREATE SCHEMA IF NOT EXISTS #{@connection.quote_column_name(@schema)}")
          end

          def set_search_path
            @connection.schema_search_path = "#{@schema}, public"
          end

          def shadow_migration_tables
            shadow = Shadow.new(@connection, self)
            shadow.call("schema_migrations")
            shadow.call("ar_internal_metadata")
          end
        end
      end
    end
  end
end
