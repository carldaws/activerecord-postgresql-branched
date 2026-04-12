require "stringio"

module ActiveRecord
  module ConnectionAdapters
    module PostgreSQL
      module Branched
        module SchemaDumperExtension
          private

          def on_branch?
            @connection.respond_to?(:branch_manager) &&
              @connection.branch_manager &&
              !@connection.branch_manager.primary_branch?
          end

          def initialize(connection, options = {})
            super
            @dump_schemas = ["public"] if on_branch?
          end

          def schemas(stream)
            return if on_branch?
            super
          end

          def tables(stream)
            return super unless on_branch?

            table_names = @connection.tables.uniq.sort
            table_names.reject! { |t| ignored?(t) }

            table_names.each_with_index do |table_name, index|
              table(table_name, stream)
              stream.puts if index < table_names.size - 1
            end

            if @connection.supports_foreign_keys?
              fk_stream = StringIO.new
              table_names.each { |tbl| foreign_keys(tbl, fk_stream) }
              fk_string = fk_stream.string
              if fk_string.length > 0
                stream.puts
                stream.print fk_string
              end
            end
          end

          def types(stream)
            return super unless on_branch?

            enums = @connection.enum_types
            if enums.any?
              stream.puts "  # Custom types defined in this database."
              stream.puts "  # Note that some types may not work with other database engines. Be careful if changing database."
              enums.sort.each do |name, values|
                stream.puts "  create_enum #{name.inspect}, #{values.inspect}"
              end
              stream.puts
            end
          end
        end
      end
    end
  end
end
