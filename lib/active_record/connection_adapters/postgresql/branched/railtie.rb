module ActiveRecord
  module ConnectionAdapters
    module PostgreSQL
      module Branched
        class Railtie < Rails::Railtie
          rake_tasks do
            namespace :db do
              namespace :branch do
                desc "Drop and recreate the current branch schema"
                task reset: :load_config do
                  connection = ActiveRecord::Base.lease_connection
                  manager = BranchManager.new(connection)

                  if manager.primary_branch?
                    puts "On primary branch (#{manager.branch}), nothing to reset."
                    next
                  end

                  schema = manager.schema
                  connection.execute("DROP SCHEMA IF EXISTS #{connection.quote_column_name(schema)} CASCADE")
                  connection.execute("CREATE SCHEMA #{connection.quote_column_name(schema)}")
                  connection.execute("SET search_path TO #{schema}, public")
                  puts "Reset branch schema #{schema}. Run db:migrate to reapply branch migrations."
                end

                desc "Drop the current branch schema entirely"
                task discard: :load_config do
                  connection = ActiveRecord::Base.lease_connection
                  branch_name = ENV["BRANCH"] || ENV["PGBRANCH"] || `git branch --show-current`.strip
                  schema = BranchManager.sanitise(branch_name)

                  if schema == BranchManager.sanitise(connection.pool.db_config.configuration_hash[:primary_branch] || "main")
                    puts "Cannot discard the primary branch schema."
                    next
                  end

                  connection.execute("DROP SCHEMA IF EXISTS #{connection.quote_column_name(schema)} CASCADE")
                  puts "Discarded branch schema #{schema}."
                end

                desc "List all branch schemas and their sizes"
                task list: :load_config do
                  connection = ActiveRecord::Base.lease_connection
                  rows = connection.select_rows(<<~SQL)
                    SELECT schema_name,
                           pg_size_pretty(sum(pg_total_relation_size(quote_ident(schema_name) || '.' || quote_ident(table_name)))) AS size
                    FROM information_schema.tables
                    WHERE schema_name LIKE 'pgb_%'
                    GROUP BY schema_name
                    ORDER BY schema_name
                  SQL

                  if rows.empty?
                    puts "No branch schemas found."
                  else
                    puts "Branch schemas:"
                    rows.each { |name, size| puts "  #{name} (#{size})" }
                  end
                end

                desc "Show objects in the current branch schema vs public"
                task diff: :load_config do
                  connection = ActiveRecord::Base.lease_connection
                  manager = BranchManager.new(connection)

                  if manager.primary_branch?
                    puts "On primary branch, no diff."
                    next
                  end

                  branch_tables = connection.select_values(<<~SQL)
                    SELECT table_name FROM information_schema.tables
                    WHERE table_schema = #{connection.quote(manager.schema)} AND table_type = 'BASE TABLE'
                    ORDER BY table_name
                  SQL

                  if branch_tables.empty?
                    puts "No branch-local objects in #{manager.schema}."
                  else
                    puts "Branch-local objects in #{manager.schema}:"
                    branch_tables.each { |t| puts "  #{t}" }
                  end
                end
              end
            end
          end

          initializer "postgresql_branched.schema_dumper" do
            ActiveSupport.on_load(:active_record) do
              ActiveRecord::ConnectionAdapters::PostgreSQL::SchemaDumper.prepend(
                ActiveRecord::ConnectionAdapters::PostgreSQL::Branched::SchemaDumperExtension
              )
            end
          end
        end
      end
    end
  end
end
