require "minitest/autorun"
require "active_record"
require "activerecord-postgresql-branched"

DATABASE_NAME = "pgb_test"
DATABASE_URL = "postgres://localhost/#{DATABASE_NAME}"

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
  end

  def connect(branch_override: nil, primary_branch: "main")
    config = {
      adapter: "postgresql_branched",
      database: DATABASE_NAME,
      primary_branch: primary_branch
    }
    config[:branch_override] = branch_override if branch_override
    ActiveRecord::Base.establish_connection(config)
    ActiveRecord::Base.lease_connection
  end

  def raw_pg
    PG.connect(dbname: DATABASE_NAME)
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
end
