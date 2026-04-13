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
                  manager = branch_manager
                  manager.reset
                  puts "Reset branch schema #{manager.branch_schema}. Run db:migrate to reapply branch migrations."
                end

                desc "Drop a branch schema (current branch or BRANCH=name)"
                task discard: :load_config do
                  manager = branch_manager
                  branch = ENV["BRANCH"] || manager.branch
                  schema = BranchManager.sanitise(branch)

                  manager.discard(branch)
                  puts "Discarded branch schema #{schema}."
                rescue => e
                  puts e.message
                end

                desc "List all branch schemas and their sizes"
                task list: :load_config do
                  rows = branch_manager.list

                  if rows.empty?
                    puts "No branch schemas found."
                  else
                    puts "Branch schemas:"
                    rows.each { |name, size| puts "  #{name} (#{size})" }
                  end
                end

                desc "Drop schemas not in KEEP list (or not matching local git branches)"
                task prune: :load_config do
                  keep = ENV["KEEP"]&.split(",")&.map(&:strip)
                  pruned = branch_manager.prune(keep: keep)

                  if pruned.empty?
                    puts "No stale branch schemas found."
                  else
                    puts "Pruned #{pruned.size} stale branch schema#{"s" if pruned.size > 1}:"
                    pruned.each { |s| puts "  #{s}" }
                  end
                end

                desc "Show objects in the current branch schema"
                task diff: :load_config do
                  manager = branch_manager
                  tables = manager.diff

                  if tables.empty?
                    puts "No branch-local objects in #{manager.branch_schema}."
                  else
                    puts "Branch-local objects in #{manager.branch_schema}:"
                    tables.each { |t| puts "  #{t}" }
                  end
                end
              end
            end

            def branch_manager
              ActiveRecord::Base.lease_connection.branch_manager
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
