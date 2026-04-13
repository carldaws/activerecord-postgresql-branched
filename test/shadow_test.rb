require "test_helper"

class ShadowTest < Minitest::Test
  include PGBTestSupport

  def setup
    setup_test_database

    # Establish a baseline in public via the primary branch, then switch
    # to a feature branch for the actual test. This mirrors real usage.
    conn = connect(branch: "main")
    conn.execute("CREATE TABLE public.users (id serial PRIMARY KEY, name varchar, legacy varchar)")
    conn.execute("CREATE TABLE public.orders (id serial PRIMARY KEY, status varchar, amount integer)")
    conn.execute("CREATE TABLE public.authors (id serial PRIMARY KEY, name varchar)")
    conn.execute("CREATE TABLE public.posts (id serial PRIMARY KEY, author_id integer, title varchar)")
    conn.execute("INSERT INTO public.users (name, legacy) VALUES ('alice', 'old'), ('bob', 'old')")
    conn.execute("INSERT INTO public.orders (status, amount) VALUES ('pending', 100)")
    conn.execute("INSERT INTO public.authors (name) VALUES ('alice')")
    conn.execute("INSERT INTO public.posts (author_id, title) VALUES (1, 'hello')")
  end

  def teardown
    teardown_test_database
  end

  # --- Shadow behavior ---

  def test_shadow_copies_structure_and_data
    conn = reconnect(branch: "feature/shadow")
    conn.add_column :users, :bio, :string

    assert table_exists_in_schema?(conn, "branch_feature_shadow", "users")
    count = conn.select_value("SELECT count(*) FROM users")
    assert_equal 2, count, "Shadow must copy data from public"
  end

  def test_shadow_does_not_duplicate_on_second_ddl
    conn = reconnect(branch: "feature/shadow")
    conn.add_column :users, :bio, :string
    conn.add_column :users, :age, :integer

    count = conn.select_value("SELECT count(*) FROM branch_feature_shadow.users")
    assert_equal 2, count, "Data must not be duplicated by second DDL"
  end

  def test_shadow_not_triggered_for_branch_only_table
    conn = reconnect(branch: "feature/new-table")
    conn.create_table(:payments) { |t| t.integer :amount }

    assert table_exists_in_schema?(conn, "branch_feature_new_table", "payments")
    refute table_exists_in_schema?(conn, "public", "payments")
  end

  def test_shadow_not_triggered_on_primary_branch
    conn = reconnect(branch: "main")
    conn.add_column :users, :bio, :string

    assert column_exists_in_schema?(conn, "public", "users", "bio"),
      "On primary branch, DDL must modify public directly"
    refute schema_exists?(conn, "branch_main")
  end

  def test_shadow_leaves_public_untouched
    conn = reconnect(branch: "feature/shadow")
    conn.add_column :users, :bio, :string

    refute column_exists_in_schema?(conn, "public", "users", "bio"),
      "Public must not be modified by feature branch DDL"
  end

  # --- Column DDL ---

  def test_add_column_triggers_shadow
    conn = reconnect(branch: "feature/add-col")
    refute table_exists_in_schema?(conn, "branch_feature_add_col", "users")

    conn.add_column :users, :bio, :string

    assert table_exists_in_schema?(conn, "branch_feature_add_col", "users")
    assert column_exists_in_schema?(conn, "branch_feature_add_col", "users", "bio")
  end

  def test_remove_column_triggers_shadow
    conn = reconnect(branch: "feature/rm-col")
    conn.remove_column :users, :legacy

    assert table_exists_in_schema?(conn, "branch_feature_rm_col", "users")
    refute column_exists_in_schema?(conn, "branch_feature_rm_col", "users", "legacy")
    assert column_exists_in_schema?(conn, "public", "users", "legacy"),
      "Public column must be untouched"
  end

  def test_rename_column_triggers_shadow
    conn = reconnect(branch: "feature/ren-col")
    conn.rename_column :users, :legacy, :old_field

    assert table_exists_in_schema?(conn, "branch_feature_ren_col", "users")
    refute column_exists_in_schema?(conn, "branch_feature_ren_col", "users", "legacy")
    assert column_exists_in_schema?(conn, "branch_feature_ren_col", "users", "old_field")
  end

  def test_change_column_triggers_shadow
    conn = reconnect(branch: "feature/chg-col")
    conn.change_column :users, :name, :text

    assert table_exists_in_schema?(conn, "branch_feature_chg_col", "users")
  end

  def test_change_column_default_triggers_shadow
    conn = reconnect(branch: "feature/chg-default")
    conn.change_column_default :users, :name, "unknown"

    assert table_exists_in_schema?(conn, "branch_feature_chg_default", "users")
  end

  def test_change_column_null_triggers_shadow
    conn = reconnect(branch: "feature/chg-null")
    conn.change_column_null :users, :name, false, "unknown"

    assert table_exists_in_schema?(conn, "branch_feature_chg_null", "users")
  end

  # --- Index DDL ---

  def test_add_index_triggers_shadow
    conn = reconnect(branch: "feature/add-idx")
    conn.add_index :orders, :status

    assert table_exists_in_schema?(conn, "branch_feature_add_idx", "orders")
    assert index_exists_in_schema?(conn, "branch_feature_add_idx", "index_orders_on_status")
  end

  def test_remove_index_triggers_shadow
    conn = reconnect(branch: "feature/rm-idx")
    conn.add_index :orders, :status, name: "idx_orders_status"
    conn.remove_index :orders, name: "idx_orders_status"

    assert table_exists_in_schema?(conn, "branch_feature_rm_idx", "orders")
    refute index_exists_in_schema?(conn, "branch_feature_rm_idx", "idx_orders_status")
  end

  def test_rename_index_triggers_shadow
    conn = reconnect(branch: "feature/ren-idx")
    conn.add_index :orders, :status, name: "idx_old"
    conn.rename_index :orders, "idx_old", "idx_new"

    assert index_exists_in_schema?(conn, "branch_feature_ren_idx", "idx_new")
    refute index_exists_in_schema?(conn, "branch_feature_ren_idx", "idx_old")
  end

  # --- Foreign key DDL ---

  def test_add_foreign_key_triggers_shadow
    conn = reconnect(branch: "feature/add-fk")
    refute table_exists_in_schema?(conn, "branch_feature_add_fk", "posts")

    conn.add_foreign_key :posts, :authors

    assert table_exists_in_schema?(conn, "branch_feature_add_fk", "posts"),
      "add_foreign_key must shadow the table"
    assert table_exists_in_schema?(conn, "public", "posts"),
      "Public must be untouched"
  end

  def test_remove_foreign_key_triggers_shadow
    conn = reconnect(branch: "feature/rm-fk")
    conn.add_foreign_key :posts, :authors
    conn.remove_foreign_key :posts, :authors

    assert table_exists_in_schema?(conn, "branch_feature_rm_fk", "posts")
  end

  # --- Check constraint DDL ---

  def test_add_check_constraint_triggers_shadow
    conn = reconnect(branch: "feature/add-check")
    refute table_exists_in_schema?(conn, "branch_feature_add_check", "orders")

    conn.add_check_constraint :orders, "amount > 0", name: "amount_positive"

    assert table_exists_in_schema?(conn, "branch_feature_add_check", "orders")
    assert check_constraint_exists_in_schema?(conn, "branch_feature_add_check", "orders", "amount_positive")
  end

  def test_remove_check_constraint_triggers_shadow
    conn = reconnect(branch: "feature/rm-check")
    conn.add_check_constraint :orders, "amount > 0", name: "amount_positive"
    conn.remove_check_constraint :orders, name: "amount_positive"

    assert table_exists_in_schema?(conn, "branch_feature_rm_check", "orders")
    refute check_constraint_exists_in_schema?(conn, "branch_feature_rm_check", "orders", "amount_positive")
  end

  # --- Table-level DDL ---

  def test_drop_table_shadows_then_drops
    conn = reconnect(branch: "feature/drop")
    conn.drop_table :orders

    assert table_exists_in_schema?(conn, "public", "orders"),
      "Public table must not be affected"
    refute table_exists_in_schema?(conn, "branch_feature_drop", "orders"),
      "Shadow must be dropped"
  end

  def test_rename_table_shadows_then_renames
    conn = reconnect(branch: "feature/rename")
    conn.rename_table :orders, :purchases

    assert table_exists_in_schema?(conn, "public", "orders"),
      "Public must still have original table"
    assert table_exists_in_schema?(conn, "branch_feature_rename", "purchases"),
      "Branch must have renamed table"
    refute table_exists_in_schema?(conn, "branch_feature_rename", "orders")

    result = conn.select_value("SELECT status FROM purchases LIMIT 1")
    assert_equal "pending", result, "Data must be preserved through rename"
  end

  def test_change_table_triggers_shadow
    conn = reconnect(branch: "feature/chg-table")
    conn.change_table :users do |t|
      t.string :nickname
    end

    assert table_exists_in_schema?(conn, "branch_feature_chg_table", "users")
    assert column_exists_in_schema?(conn, "branch_feature_chg_table", "users", "nickname")
  end

  # --- Foreign key preservation through shadow ---

  def test_shadow_preserves_data_accessible_via_foreign_key
    conn = reconnect(branch: "feature/fk-data")

    # Add FK and a body column
    conn.add_foreign_key :posts, :authors
    conn.add_column :posts, :body, :text

    count = conn.select_value("SELECT count(*) FROM posts")
    assert_equal 1, count

    # Can insert with valid FK reference (authors is in public via fallthrough)
    author_id = conn.select_value("SELECT id FROM authors LIMIT 1")
    conn.execute("INSERT INTO posts (author_id, title, body) VALUES (#{author_id}, 'world', 'content')")
    assert_equal 2, conn.select_value("SELECT count(*) FROM posts")
  end
end
