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
    conn.create_table(:widgets) { |t| t.string :name; t.integer :price }

    output = dump_schema(conn)

    assert_includes output, "create_table"
    assert_includes output, "widgets"
    refute_includes output, "branch_"
  end

  def test_dump_branch_with_shadowed_table
    main_conn = connect(branch: "main")
    main_conn.create_table(:users) { |t| t.string :name }

    conn = reconnect(branch: "feature/dump2")
    conn.add_column :users, :bio, :string

    output = dump_schema(conn)

    assert_includes output, "users"
    assert_includes output, "bio"
    refute_includes output, "branch_"
  end

  def test_dump_includes_public_tables
    main_conn = connect(branch: "main")
    main_conn.create_table(:products) { |t| t.string :title }

    conn = reconnect(branch: "feature/dump3")
    conn.create_table(:widgets) { |t| t.string :name }

    output = dump_schema(conn)

    assert_includes output, "products", "Public tables should appear in dump"
    assert_includes output, "widgets", "Branch tables should appear in dump"
    refute_includes output, "branch_"
  end

  def test_dump_on_primary_branch_is_standard
    conn = connect(branch: "main")
    conn.create_table(:products) { |t| t.string :title }

    output = dump_schema(conn)

    assert_includes output, "products"
    refute_includes output, "branch_"
    refute_includes output, "create_schema"
  end

  private

  def dump_schema(conn)
    stream = StringIO.new
    conn.create_schema_dumper({}).dump(stream)
    stream.string
  end
end
