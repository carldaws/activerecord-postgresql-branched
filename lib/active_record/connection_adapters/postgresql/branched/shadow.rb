module ActiveRecord
  module ConnectionAdapters
    module PostgreSQL
      module Branched
        class Shadow
          def initialize(connection, branch_schema)
            @connection = connection
            @branch_schema = branch_schema
          end

          def call(table_name)
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
              WHERE table_schema = #{@connection.quote(@branch_schema)}
                AND table_name = #{@connection.quote(table)}
            SQL
          end

          def create_shadow(table)
            quoted_branch = @connection.quote_column_name(@branch_schema)
            quoted_table = @connection.quote_column_name(table)

            clone_structure(quoted_branch, quoted_table)
            copy_data(quoted_branch, quoted_table)
            clone_indexes(table, quoted_branch, quoted_table)
            clone_constraints(table, quoted_branch, quoted_table)
          end

          # Per-row index maintenance during INSERT SELECT dominates the cost
          # of shadowing large tables. LIKE ... INCLUDING ALL builds every
          # index up front, then the data copy updates each index for every
          # row. EXCLUDING INDEXES lets the bulk copy run without index
          # overhead; clone_indexes rebuilds them afterwards in a single
          # sort pass per index, the standard Postgres bulk-load pattern.
          def clone_structure(quoted_branch, quoted_table)
            @connection.execute(<<~SQL)
              CREATE TABLE #{quoted_branch}.#{quoted_table}
                (LIKE public.#{quoted_table} INCLUDING ALL EXCLUDING INDEXES)
            SQL
          end

          def copy_data(quoted_branch, quoted_table)
            @connection.execute(<<~SQL)
              INSERT INTO #{quoted_branch}.#{quoted_table}
                SELECT * FROM public.#{quoted_table}
            SQL
          end

          def clone_indexes(table, quoted_branch, quoted_table)
            index_metadata(table).each do |index_name, is_primary, branched_indexdef|
              @connection.execute(branched_indexdef)

              next unless is_primary

              quoted_index = @connection.quote_column_name(index_name)
              @connection.execute(<<~SQL)
                ALTER TABLE #{quoted_branch}.#{quoted_table}
                  ADD CONSTRAINT #{quoted_index} PRIMARY KEY USING INDEX #{quoted_index}
              SQL
            end
          end

          # LIKE ... INCLUDING ALL EXCLUDING INDEXES drops all index-backed
          # constraints (PK, unique, exclusion). clone_constraints re-emits
          # unique and exclusion constraints which implicitly create their
          # backing indexes, so we skip those here to avoid name collisions.
          # PK indexes are rebuilt and reattached via USING INDEX.
          def index_metadata(table)
            @connection.select_rows(<<~SQL)
              SELECT i.relname, ix.indisprimary,
                REPLACE(
                  pg_get_indexdef(ix.indexrelid),
                  ' ON public.' || quote_ident(t.relname),
                  ' ON ' || quote_ident(#{@connection.quote(@branch_schema)}) || '.' || quote_ident(t.relname)
                )
              FROM pg_index ix
                JOIN pg_class i ON i.oid = ix.indexrelid
                JOIN pg_class t ON t.oid = ix.indrelid
                JOIN pg_namespace n ON n.oid = t.relnamespace
              WHERE n.nspname = 'public'
                AND t.relname = #{@connection.quote(table)}
                AND NOT EXISTS (
                  SELECT 1 FROM pg_constraint c
                  WHERE c.conindid = ix.indexrelid
                    AND c.contype IN ('x', 'u')
                )
            SQL
          end

          # LIKE ... INCLUDING CONSTRAINTS copies check constraints and NOT
          # NULL but never foreign keys (Postgres design). EXCLUDING INDEXES
          # also drops exclusion and unique constraints since they're index-
          # backed. Re-emit each from pg_constraint; the definitions from
          # pg_get_constraintdef are self-contained and resolve correctly
          # via the branch search_path without rewriting.
          def clone_constraints(table, quoted_branch, quoted_table)
            constraint_definitions(table).each do |conname, condef|
              quoted_con = @connection.quote_column_name(conname)
              @connection.execute(<<~SQL)
                ALTER TABLE #{quoted_branch}.#{quoted_table}
                  ADD CONSTRAINT #{quoted_con} #{condef}
              SQL
            end
          end

          def constraint_definitions(table)
            @connection.select_rows(<<~SQL)
              SELECT c.conname, pg_get_constraintdef(c.oid, true)
              FROM pg_constraint c
                JOIN pg_class t ON t.oid = c.conrelid
                JOIN pg_namespace n ON n.oid = t.relnamespace
              WHERE n.nspname = 'public'
                AND t.relname = #{@connection.quote(table)}
                AND c.contype IN ('f', 'x', 'u')
              ORDER BY c.conname
            SQL
          end
        end
      end
    end
  end
end
