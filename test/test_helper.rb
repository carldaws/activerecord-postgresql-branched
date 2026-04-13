require "minitest/autorun"
require "active_record"
require "activerecord-postgresql-branched"

DATABASE_NAME = "pgb_test"

ActiveRecord::ConnectionAdapters::PostgreSQL::SchemaDumper.prepend(
  ActiveRecord::ConnectionAdapters::PostgreSQL::Branched::SchemaDumperExtension
)

module PGBTestSupport
  def setup_test_database
    conn = PG.connect(dbname: "postgres")
    conn.exec("DROP DATABASE IF EXISTS #{DATABASE_NAME}")
    conn.exec("CREATE DATABASE #{DATABASE_NAME}")
    conn.close
  end

  def teardown_test_database
    ActiveRecord::Base.connection_pool.disconnect!
    conn = PG.connect(dbname: "postgres")
    conn.exec("DROP DATABASE IF EXISTS #{DATABASE_NAME}")
    conn.close
    ENV.delete("PGBRANCH")
  end

  def connect(branch:, primary_branch: "main")
    ENV["PGBRANCH"] = branch
    ActiveRecord::Base.establish_connection(
      adapter: "postgresql_branched",
      database: DATABASE_NAME,
      primary_branch: primary_branch
    )
    ActiveRecord::Base.lease_connection
  end

  def reconnect(branch:, primary_branch: "main")
    ActiveRecord::Base.connection_pool.disconnect!
    connect(branch: branch, primary_branch: primary_branch)
  end

  def schema_exists?(connection, schema_name)
    connection.select_value(
      "SELECT 1 FROM information_schema.schemata WHERE schema_name = #{connection.quote(schema_name)}"
    ) == 1
  end

  def table_exists_in_schema?(connection, schema_name, table_name)
    connection.select_value(<<~SQL) == 1
      SELECT 1 FROM information_schema.tables
      WHERE table_schema = #{connection.quote(schema_name)}
        AND table_name = #{connection.quote(table_name)}
    SQL
  end

  def column_exists_in_schema?(connection, schema_name, table_name, column_name)
    connection.select_value(<<~SQL) == 1
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = #{connection.quote(schema_name)}
        AND table_name = #{connection.quote(table_name)}
        AND column_name = #{connection.quote(column_name)}
    SQL
  end

  def index_exists_in_schema?(connection, schema_name, index_name)
    connection.select_value(<<~SQL) == 1
      SELECT 1 FROM pg_indexes
      WHERE schemaname = #{connection.quote(schema_name)}
        AND indexname = #{connection.quote(index_name)}
    SQL
  end

  def foreign_key_exists_in_schema?(connection, schema_name, table_name, constraint_name)
    connection.select_value(<<~SQL) == 1
      SELECT 1 FROM information_schema.table_constraints
      WHERE constraint_schema = #{connection.quote(schema_name)}
        AND table_name = #{connection.quote(table_name)}
        AND constraint_type = 'FOREIGN KEY'
        AND constraint_name = #{connection.quote(constraint_name)}
    SQL
  end

  def check_constraint_exists_in_schema?(connection, schema_name, table_name, constraint_name)
    connection.select_value(<<~SQL) == 1
      SELECT 1 FROM information_schema.table_constraints
      WHERE constraint_schema = #{connection.quote(schema_name)}
        AND table_name = #{connection.quote(table_name)}
        AND constraint_type = 'CHECK'
        AND constraint_name = #{connection.quote(constraint_name)}
    SQL
  end
end
