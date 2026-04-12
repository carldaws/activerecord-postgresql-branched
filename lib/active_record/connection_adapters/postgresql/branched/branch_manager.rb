module ActiveRecord
  module ConnectionAdapters
    module PostgreSQL
      module Branched
        class BranchManager
          attr_reader :branch, :branch_schema

          def initialize(connection, config)
            @connection = connection
            @config = config
            @branch = resolve_branch
            @branch_schema = self.class.sanitise(@branch)
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

          def reset
            drop_schema
            ensure_schema
            set_search_path
          end

          def discard(branch_name = @branch)
            schema = self.class.sanitise(branch_name)

            if schema == self.class.sanitise(primary_branch_name)
              raise "Cannot discard the primary branch schema"
            end

            @connection.execute("DROP SCHEMA IF EXISTS #{quote(schema)} CASCADE")
          end

          def list
            @connection.select_rows(<<~SQL)
              SELECT table_schema,
                     pg_size_pretty(sum(pg_total_relation_size(
                       quote_ident(table_schema) || '.' || quote_ident(table_name)
                     ))) AS size
              FROM information_schema.tables
              WHERE table_schema LIKE 'branch_%'
              GROUP BY table_schema
              ORDER BY table_schema
            SQL
          end

          def diff
            return [] if primary_branch?

            @connection.select_values(<<~SQL)
              SELECT table_name FROM information_schema.tables
              WHERE table_schema = #{@connection.quote(@branch_schema)}
                AND table_type = 'BASE TABLE'
              ORDER BY table_name
            SQL
          end

          def self.sanitise(branch)
            "branch_" + branch.downcase.gsub(/[\/\-\.]/, "_").gsub(/[^a-z0-9_]/, "")
          end

          def self.resolve_branch_name(config)
            config[:branch_override]&.to_s ||
              ENV["BRANCH"] ||
              ENV["PGBRANCH"] ||
              git_branch
          end

          private

          def resolve_branch
            name = self.class.resolve_branch_name(@config)

            if name.nil? || name.empty?
              raise "Could not determine git branch. " \
                    "Set branch_override in database.yml or the PGBRANCH environment variable."
            end

            name
          end

          def primary_branch_name
            (@config[:primary_branch] || "main").to_s
          end

          def ensure_schema
            @connection.execute("CREATE SCHEMA IF NOT EXISTS #{quote(@branch_schema)}")
          end

          def drop_schema
            @connection.execute("DROP SCHEMA IF EXISTS #{quote(@branch_schema)} CASCADE")
          end

          def set_search_path
            @connection.schema_search_path = "#{@branch_schema}, public"
          end

          def shadow_migration_tables
            shadow = Shadow.new(@connection, @branch_schema)
            shadow.call(ActiveRecord::Base.schema_migrations_table_name)
            shadow.call(ActiveRecord::Base.internal_metadata_table_name)
          end

          def quote(identifier)
            @connection.quote_column_name(identifier)
          end

          def self.git_branch
            result = `git branch --show-current 2>/dev/null`.strip
            result.empty? ? nil : result
          end
        end
      end
    end
  end
end
