module ActiveRecord
  module ConnectionAdapters
    module PostgreSQL
      module Branched
        class Shadow
          def initialize(connection, branch_manager)
            @connection = connection
            @branch_manager = branch_manager
          end

          def call(table_name)
            return if @branch_manager.primary_branch?

            table = table_name.to_s
            return unless exists_in_public?(table)
            return if already_shadowed?(table)

            create_shadow(table)
          end

          private

          def exists_in_public?(table)
            @connection.select_value(<<~SQL) == 1
              SELECT 1 FROM information_schema.tables
              WHERE table_schema = 'public' AND table_name = #{@connection.quote(table)}
            SQL
          end

          def already_shadowed?(table)
            @connection.select_value(<<~SQL) == 1
              SELECT 1 FROM information_schema.tables
              WHERE table_schema = #{@connection.quote(@branch_manager.schema)}
                AND table_name = #{@connection.quote(table)}
            SQL
          end

          def create_shadow(table)
            schema = @branch_manager.schema
            quoted_table = @connection.quote_column_name(table)
            @connection.execute(<<~SQL)
              CREATE TABLE #{schema}.#{quoted_table}
                (LIKE public.#{quoted_table} INCLUDING ALL)
            SQL
            @connection.execute(<<~SQL)
              INSERT INTO #{schema}.#{quoted_table}
                SELECT * FROM public.#{quoted_table}
            SQL
          end
        end
      end
    end
  end
end
