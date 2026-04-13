require "test_helper"
require "stringio"

class SchemaDumperTest < Minitest::Test
  include PGBTestSupport

  def setup
    setup_test_database
  end

  def teardown
    teardown_test_database
  end

  def test_dump_branch_with_new_table
    conn = connect(branch: "feature/dump")

    conn.create_table :widgets do |t|
      t.string :name
      t.integer :price
    end

    output = dump_schema(conn)

    assert_includes output, "create_table"
    assert_includes output, "widgets"
    refute_includes output, "branch_", "Schema dump should not contain branch_ references"
  end

  def test_dump_branch_with_shadowed_table
    conn = connect(branch: "feature/dump2")

    conn.execute("CREATE TABLE public.users (id serial PRIMARY KEY, name varchar)")
    conn.add_column :users, :bio, :string

    output = dump_schema(conn)

    assert_includes output, "users"
    assert_includes output, "bio"
    refute_includes output, "branch_", "Schema dump should not contain branch_ references"
  end

  def test_dump_includes_public_tables
    conn = connect(branch: "feature/dump3")

    conn.execute("CREATE TABLE public.products (id serial PRIMARY KEY, title varchar)")
    conn.create_table :widgets do |t|
      t.string :name
    end

    output = dump_schema(conn)

    assert_includes output, "products", "Public tables should appear in dump"
    assert_includes output, "widgets", "Branch tables should appear in dump"
    refute_includes output, "branch_"
  end

  private

  def dump_schema(conn)
    stream = StringIO.new
    conn.create_schema_dumper({}).dump(stream)
    stream.string
  end
end
