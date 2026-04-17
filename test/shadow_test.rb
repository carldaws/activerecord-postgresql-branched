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

  # --- Bulk-load shadow preserves every structural detail ---
  #
  # These tests exist because the shadow now skips INCLUDING INDEXES during
  # CREATE TABLE LIKE and rebuilds indexes after the data copy. They pin the
  # contract that the branch table is structurally equivalent to public.

  def test_shadow_preserves_primary_key_as_primary_key
    conn = reconnect(branch: "feature/pk")
    conn.add_column :users, :bio, :string

    is_primary = conn.select_value(<<~SQL)
      SELECT ix.indisprimary FROM pg_index ix
        JOIN pg_class t ON t.oid = ix.indrelid
        JOIN pg_namespace n ON n.oid = t.relnamespace
      WHERE n.nspname = 'branch_feature_pk'
        AND t.relname = 'users'
        AND ix.indisprimary
    SQL
    assert_equal true, is_primary,
      "Shadow must attach the pkey index as a PRIMARY KEY constraint, not just a unique index"
  end

  def test_shadow_primary_key_sequence_still_works
    conn = reconnect(branch: "feature/pk-insert")
    conn.add_column :users, :bio, :string

    conn.execute("INSERT INTO users (name, legacy, bio) VALUES ('carol', 'old', 'hi')")
    inserted_id = conn.select_value("SELECT id FROM users WHERE name = 'carol'")
    refute_nil inserted_id, "Inserts into the shadow must auto-assign an id"
  end

  def test_shadow_preserves_unique_index
    conn = connect(branch: "main")
    conn.execute("CREATE UNIQUE INDEX users_name_uniq ON public.users (name)")

    conn = reconnect(branch: "feature/uniq-idx")
    conn.add_column :users, :bio, :string

    assert index_exists_in_schema?(conn, "branch_feature_uniq_idx", "users_name_uniq")
    is_unique = conn.select_value(<<~SQL)
      SELECT ix.indisunique FROM pg_index ix
        JOIN pg_class i ON i.oid = ix.indexrelid
        JOIN pg_namespace n ON n.oid = i.relnamespace
      WHERE n.nspname = 'branch_feature_uniq_idx' AND i.relname = 'users_name_uniq'
    SQL
    assert_equal true, is_unique, "Unique index must be rebuilt as unique"

    assert_raises(ActiveRecord::RecordNotUnique) do
      conn.execute("INSERT INTO users (name, legacy, bio) VALUES ('alice', 'new', 'dup')")
    end
  end

  def test_shadow_preserves_non_unique_index
    conn = connect(branch: "main")
    conn.execute("CREATE INDEX users_legacy_idx ON public.users (legacy)")

    conn = reconnect(branch: "feature/plain-idx")
    conn.add_column :users, :bio, :string

    assert index_exists_in_schema?(conn, "branch_feature_plain_idx", "users_legacy_idx")
  end

  def test_shadow_preserves_check_constraint
    conn = connect(branch: "main")
    conn.execute("ALTER TABLE public.orders ADD CONSTRAINT orders_amount_positive CHECK (amount > 0)")

    conn = reconnect(branch: "feature/check")
    conn.add_column :orders, :note, :string

    assert check_constraint_exists_in_schema?(conn, "branch_feature_check", "orders", "orders_amount_positive")
    assert_raises(ActiveRecord::StatementInvalid) do
      conn.execute("INSERT INTO orders (status, amount, note) VALUES ('bad', -1, 'x')")
    end
  end

  def test_shadow_preserves_not_null_and_default
    conn = connect(branch: "main")
    conn.execute("ALTER TABLE public.orders ALTER COLUMN status SET NOT NULL")
    conn.execute("ALTER TABLE public.orders ALTER COLUMN status SET DEFAULT 'pending'")

    conn = reconnect(branch: "feature/default")
    conn.add_column :orders, :note, :string

    is_not_null = conn.select_value(<<~SQL)
      SELECT attnotnull FROM pg_attribute a
        JOIN pg_class t ON t.oid = a.attrelid
        JOIN pg_namespace n ON n.oid = t.relnamespace
      WHERE n.nspname = 'branch_feature_default'
        AND t.relname = 'orders'
        AND a.attname = 'status'
    SQL
    assert_equal true, is_not_null, "NOT NULL must survive shadow"

    conn.execute("INSERT INTO orders (amount, note) VALUES (50, 'uses-default')")
    status = conn.select_value("SELECT status FROM orders WHERE note = 'uses-default'")
    assert_equal "pending", status, "Default must survive shadow"
  end

  def test_shadow_preserves_multi_column_index
    conn = connect(branch: "main")
    conn.execute("CREATE INDEX orders_status_amount ON public.orders (status, amount)")

    conn = reconnect(branch: "feature/multi-col")
    conn.add_column :orders, :note, :string

    columns = conn.select_values(<<~SQL)
      SELECT a.attname FROM pg_index ix
        JOIN pg_class i ON i.oid = ix.indexrelid
        JOIN pg_namespace n ON n.oid = i.relnamespace
        JOIN pg_attribute a ON a.attrelid = ix.indrelid AND a.attnum = ANY(ix.indkey)
      WHERE n.nspname = 'branch_feature_multi_col' AND i.relname = 'orders_status_amount'
      ORDER BY array_position(ix.indkey, a.attnum)
    SQL
    assert_equal %w[status amount], columns, "Column order in multi-column index must be preserved"
  end

  def test_shadow_preserves_functional_and_partial_indexes
    conn = connect(branch: "main")
    # Functional and partial indexes give pg_get_indexdef more complex output —
    # exactly the case where a naive " ON public." string replacement could go
    # wrong. The rewrite must still target only the table qualifier.
    conn.execute("CREATE INDEX users_lower_name ON public.users (lower(name))")
    conn.execute("CREATE INDEX users_non_legacy ON public.users (name) WHERE legacy IS NULL")

    conn = reconnect(branch: "feature/fn-idx")
    conn.add_column :users, :bio, :string

    assert index_exists_in_schema?(conn, "branch_feature_fn_idx", "users_lower_name")
    assert index_exists_in_schema?(conn, "branch_feature_fn_idx", "users_non_legacy")
  end

  def test_shadow_preserves_indexes_on_quoted_table_name
    # A table whose name happens to need SQL quoting (capital letters, reserved
    # word, etc.) surfaces quoting bugs in the index-rewrite path. pg_get_indexdef
    # quotes only when necessary; the adapter's Ruby-side quoting always does.
    # Mismatched expectations here made the first take on this rewrite fail.
    conn = connect(branch: "main")
    conn.execute('CREATE TABLE public."User" (id serial PRIMARY KEY, email varchar)')
    conn.execute('CREATE INDEX user_email_idx ON public."User" (email)')
    conn.execute("INSERT INTO public.\"User\" (email) VALUES ('a@x.com')")

    conn = reconnect(branch: "feature/quoted-name")
    conn.add_column "User", :bio, :string

    assert table_exists_in_schema?(conn, "branch_feature_quoted_name", "User")
    assert index_exists_in_schema?(conn, "branch_feature_quoted_name", "user_email_idx")
    assert_equal 1, conn.select_value('SELECT count(*) FROM "User"')
  end

  # --- unlogged_branches option ---
  #
  # pg_class.relpersistence values:
  #   'p' = permanent (default), 'u' = unlogged, 't' = temporary

  def test_shadow_is_logged_by_default
    conn = reconnect(branch: "feature/logged")
    conn.add_column :users, :bio, :string

    assert_equal "p", relpersistence(conn, "branch_feature_logged", "users")
  end

  def test_shadow_is_unlogged_when_enabled
    conn = reconnect(branch: "feature/unlogged", unlogged_branches: true)
    conn.add_column :users, :bio, :string

    assert_equal "u", relpersistence(conn, "branch_feature_unlogged", "users")
  end

  def test_unlogged_shadow_still_has_primary_key_and_data
    conn = reconnect(branch: "feature/unlogged-pk", unlogged_branches: true)
    conn.add_column :users, :bio, :string

    assert_equal 2, conn.select_value("SELECT count(*) FROM users"),
      "Unlogged shadow must still copy data"
    is_primary = conn.select_value(<<~SQL)
      SELECT ix.indisprimary FROM pg_index ix
        JOIN pg_class t ON t.oid = ix.indrelid
        JOIN pg_namespace n ON n.oid = t.relnamespace
      WHERE n.nspname = 'branch_feature_unlogged_pk'
        AND t.relname = 'users'
        AND ix.indisprimary
    SQL
    assert_equal true, is_primary, "Unlogged shadow must keep the PK designation"
  end

  def test_unlogged_indexes_inherit_unlogged_status
    conn = connect(branch: "main")
    conn.execute("CREATE INDEX users_name_idx ON public.users (name)")

    conn = reconnect(branch: "feature/unlogged-idx", unlogged_branches: true)
    conn.add_column :users, :bio, :string

    index_persistence = conn.select_value(<<~SQL)
      SELECT c.relpersistence FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'branch_feature_unlogged_idx'
        AND c.relname = 'users_name_idx'
    SQL
    assert_equal "u", index_persistence,
      "Indexes on unlogged tables must themselves be unlogged"
  end

  def test_unlogged_option_is_ignored_on_primary_branch
    conn = reconnect(branch: "main", unlogged_branches: true)
    conn.add_column :users, :bio, :string

    assert_equal "p", relpersistence(conn, "public", "users"),
      "Primary branch must never create UNLOGGED tables — public holds the canonical data"
  end
end
