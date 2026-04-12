require "test_helper"

class ShadowTest < Minitest::Test
  include PGBTestSupport

  def setup
    setup_test_database
  end

  def teardown
    teardown_test_database
  end

  def test_add_column_shadows_from_public
    conn = connect(branch_override: "feature/shadow")

    conn.execute("CREATE TABLE public.users (id serial PRIMARY KEY, name varchar)")
    conn.execute("INSERT INTO public.users (name) VALUES ('alice'), ('bob')")

    refute table_exists_in_schema?(conn, "branch_feature_shadow", "users")

    conn.add_column :users, :bio, :string

    assert table_exists_in_schema?(conn, "branch_feature_shadow", "users"),
      "users should be shadowed after add_column"

    assert column_exists_in_schema?(conn, "branch_feature_shadow", "users", "bio"),
      "bio column should exist in the shadowed table"

    count = conn.select_value("SELECT count(*) FROM users")
    assert_equal 2, count, "Shadowed table should contain copied data"
  end

  def test_shadow_does_not_duplicate_on_second_ddl
    conn = connect(branch_override: "feature/shadow2")

    conn.execute("CREATE TABLE public.users (id serial PRIMARY KEY, name varchar)")
    conn.execute("INSERT INTO public.users (name) VALUES ('alice')")

    conn.add_column :users, :bio, :string
    conn.add_column :users, :age, :integer

    count = conn.select_value("SELECT count(*) FROM branch_feature_shadow2.users")
    assert_equal 1, count, "Data should not be duplicated by second DDL"
  end

  def test_shadow_not_triggered_on_primary_branch
    conn = connect(branch_override: "main")

    conn.execute("CREATE TABLE public.users (id serial PRIMARY KEY, name varchar)")
    conn.add_column :users, :bio, :string

    assert column_exists_in_schema?(conn, "public", "users", "bio"),
      "On primary branch, add_column should modify public directly"
  end

  def test_shadow_not_triggered_for_branch_only_table
    conn = connect(branch_override: "feature/new-table")

    conn.create_table :payments do |t|
      t.integer :amount
    end

    assert table_exists_in_schema?(conn, "branch_feature_new_table", "payments"),
      "New table should be in branch schema"
    refute table_exists_in_schema?(conn, "public", "payments"),
      "New table should NOT be in public"
  end

  def test_add_index_triggers_shadow
    conn = connect(branch_override: "feature/idx")

    conn.execute("CREATE TABLE public.orders (id serial PRIMARY KEY, status varchar)")
    conn.execute("INSERT INTO public.orders (status) VALUES ('pending')")

    conn.add_index :orders, :status

    assert table_exists_in_schema?(conn, "branch_feature_idx", "orders"),
      "orders should be shadowed after add_index"
  end

  def test_remove_column_triggers_shadow
    conn = connect(branch_override: "feature/rm-col")

    conn.execute("CREATE TABLE public.users (id serial PRIMARY KEY, name varchar, legacy varchar)")
    conn.execute("INSERT INTO public.users (name, legacy) VALUES ('alice', 'old')")

    conn.remove_column :users, :legacy

    assert table_exists_in_schema?(conn, "branch_feature_rm_col", "users"),
      "users should be shadowed after remove_column"
    refute column_exists_in_schema?(conn, "branch_feature_rm_col", "users", "legacy"),
      "legacy column should be gone from shadowed table"

    assert column_exists_in_schema?(conn, "public", "users", "legacy"),
      "public table should still have legacy column"
  end

  def test_drop_table_shadows_then_drops
    conn = connect(branch_override: "feature/drop")

    conn.execute("CREATE TABLE public.legacy (id serial PRIMARY KEY)")

    conn.drop_table :legacy

    assert table_exists_in_schema?(conn, "public", "legacy"),
      "Public table should not be affected by drop on branch"
    refute table_exists_in_schema?(conn, "branch_feature_drop", "legacy"),
      "Shadow should have been dropped"
  end
end
