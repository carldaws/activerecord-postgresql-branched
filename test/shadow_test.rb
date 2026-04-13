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
    conn = connect(branch: "feature/shadow")

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
    conn = connect(branch: "feature/shadow2")

    conn.execute("CREATE TABLE public.users (id serial PRIMARY KEY, name varchar)")
    conn.execute("INSERT INTO public.users (name) VALUES ('alice')")

    conn.add_column :users, :bio, :string
    conn.add_column :users, :age, :integer

    count = conn.select_value("SELECT count(*) FROM branch_feature_shadow2.users")
    assert_equal 1, count, "Data should not be duplicated by second DDL"
  end

  def test_shadow_not_triggered_for_branch_only_table
    conn = connect(branch: "feature/new-table")

    conn.create_table :payments do |t|
      t.integer :amount
    end

    assert table_exists_in_schema?(conn, "branch_feature_new_table", "payments"),
      "New table should be in branch schema"
    refute table_exists_in_schema?(conn, "public", "payments"),
      "New table should NOT be in public"
  end

  def test_add_index_triggers_shadow
    conn = connect(branch: "feature/idx")

    conn.execute("CREATE TABLE public.orders (id serial PRIMARY KEY, status varchar)")
    conn.execute("INSERT INTO public.orders (status) VALUES ('pending')")

    conn.add_index :orders, :status

    assert table_exists_in_schema?(conn, "branch_feature_idx", "orders"),
      "orders should be shadowed after add_index"
  end

  def test_remove_column_triggers_shadow
    conn = connect(branch: "feature/rm-col")

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
    conn = connect(branch: "feature/drop")

    conn.execute("CREATE TABLE public.legacy (id serial PRIMARY KEY)")

    conn.drop_table :legacy

    assert table_exists_in_schema?(conn, "public", "legacy"),
      "Public table should not be affected by drop on branch"
    refute table_exists_in_schema?(conn, "branch_feature_drop", "legacy"),
      "Shadow should have been dropped"
  end

  def test_rename_table_shadows_then_renames
    conn = connect(branch: "feature/rename")

    conn.execute("CREATE TABLE public.widgets (id serial PRIMARY KEY, name varchar)")
    conn.execute("INSERT INTO public.widgets (name) VALUES ('gadget')")

    conn.rename_table :widgets, :gadgets

    assert table_exists_in_schema?(conn, "public", "widgets"),
      "Public widgets should still exist"

    assert table_exists_in_schema?(conn, "branch_feature_rename", "gadgets"),
      "Renamed table should exist in branch schema"
    refute table_exists_in_schema?(conn, "branch_feature_rename", "widgets"),
      "Original name should not exist in branch schema"

    result = conn.select_value("SELECT name FROM gadgets LIMIT 1")
    assert_equal "gadget", result
  end

  def test_shadow_preserves_foreign_key_to_public_table
    conn = connect(branch: "feature/fk")

    conn.execute("CREATE TABLE public.authors (id serial PRIMARY KEY, name varchar)")
    conn.execute("INSERT INTO public.authors (name) VALUES ('alice')")
    conn.execute(<<~SQL)
      CREATE TABLE public.posts (
        id serial PRIMARY KEY,
        author_id integer REFERENCES public.authors(id),
        title varchar
      )
    SQL
    conn.execute("INSERT INTO public.posts (author_id, title) VALUES (1, 'hello')")

    conn.add_column :posts, :body, :text

    assert table_exists_in_schema?(conn, "branch_feature_fk", "posts"),
      "posts should be shadowed"

    count = conn.select_value("SELECT count(*) FROM posts")
    assert_equal 1, count

    author_id = conn.select_value("SELECT id FROM authors LIMIT 1")
    conn.execute("INSERT INTO posts (author_id, title, body) VALUES (#{author_id}, 'world', 'content')")
    assert_equal 2, conn.select_value("SELECT count(*) FROM posts")
  end

  def test_add_foreign_key_triggers_shadow
    conn = connect(branch: "feature/add-fk")

    conn.execute("CREATE TABLE public.authors (id serial PRIMARY KEY, name varchar)")
    conn.execute("INSERT INTO public.authors (name) VALUES ('alice')")
    conn.execute("CREATE TABLE public.posts (id serial PRIMARY KEY, author_id integer, title varchar)")
    conn.execute("INSERT INTO public.posts (author_id, title) VALUES (1, 'hello')")

    refute table_exists_in_schema?(conn, "branch_feature_add_fk", "posts")

    conn.add_foreign_key :posts, :authors

    assert table_exists_in_schema?(conn, "branch_feature_add_fk", "posts"),
      "posts should be shadowed after add_foreign_key"

    assert table_exists_in_schema?(conn, "public", "posts"),
      "public posts should be untouched"
  end

  def test_add_check_constraint_triggers_shadow
    conn = connect(branch: "feature/check")

    conn.execute("CREATE TABLE public.orders (id serial PRIMARY KEY, amount integer)")
    conn.execute("INSERT INTO public.orders (amount) VALUES (100)")

    refute table_exists_in_schema?(conn, "branch_feature_check", "orders")

    conn.add_check_constraint :orders, "amount > 0", name: "amount_positive"

    assert table_exists_in_schema?(conn, "branch_feature_check", "orders"),
      "orders should be shadowed after add_check_constraint"
  end
end
