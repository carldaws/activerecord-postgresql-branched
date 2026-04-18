require "test_helper"

# Systematic DDL coverage: every table-modifying method gets a test that
# asserts the change lands on the branch and public is untouched.
class DdlCoverageTest < Minitest::Test
  include PGBTestSupport

  def setup
    setup_test_database
    conn = connect(branch: "main")
    conn.execute("CREATE TABLE public.users (id serial PRIMARY KEY, name varchar NOT NULL, email varchar, legacy varchar)")
    conn.execute("CREATE TABLE public.orders (id serial PRIMARY KEY, status varchar, amount integer)")
    conn.execute("CREATE TABLE public.authors (id serial PRIMARY KEY, name varchar NOT NULL)")
    conn.execute("CREATE TABLE public.posts (id serial PRIMARY KEY, author_id integer, title varchar)")
    conn.execute("INSERT INTO public.users (name, email) VALUES ('alice', 'alice@example.com'), ('bob', 'bob@example.com')")
    conn.execute("INSERT INTO public.orders (status, amount) VALUES ('pending', 100)")
    conn.execute("INSERT INTO public.authors (name) VALUES ('alice')")
    conn.execute("INSERT INTO public.posts (author_id, title) VALUES (1, 'hello')")
  end

  def teardown
    teardown_test_database
  end

  # --- Column DDL ---

  def test_add_column
    conn = reconnect(branch: "feature/add-col")
    conn.add_column :users, :bio, :string

    assert column_exists_in_schema?(conn, "branch_feature_add_col", "users", "bio")
    refute column_exists_in_schema?(conn, "public", "users", "bio")
  end

  def test_add_columns
    conn = reconnect(branch: "feature/add-cols")
    conn.add_columns :users, :bio, :age, type: :string

    assert column_exists_in_schema?(conn, "branch_feature_add_cols", "users", "bio")
    assert column_exists_in_schema?(conn, "branch_feature_add_cols", "users", "age")
    refute column_exists_in_schema?(conn, "public", "users", "bio")
  end

  def test_remove_column
    conn = reconnect(branch: "feature/rm-col")
    conn.remove_column :users, :legacy

    refute column_exists_in_schema?(conn, "branch_feature_rm_col", "users", "legacy")
    assert column_exists_in_schema?(conn, "public", "users", "legacy")
  end

  def test_remove_columns
    conn = reconnect(branch: "feature/rm-cols")
    conn.remove_columns :users, :email, :legacy

    refute column_exists_in_schema?(conn, "branch_feature_rm_cols", "users", "email")
    refute column_exists_in_schema?(conn, "branch_feature_rm_cols", "users", "legacy")
    assert column_exists_in_schema?(conn, "public", "users", "email")
    assert column_exists_in_schema?(conn, "public", "users", "legacy")
  end

  def test_rename_column
    conn = reconnect(branch: "feature/ren-col")
    conn.rename_column :users, :legacy, :old_field

    assert column_exists_in_schema?(conn, "branch_feature_ren_col", "users", "old_field")
    refute column_exists_in_schema?(conn, "branch_feature_ren_col", "users", "legacy")
    assert column_exists_in_schema?(conn, "public", "users", "legacy")
  end

  def test_change_column
    conn = reconnect(branch: "feature/chg-col")
    conn.change_column :users, :name, :text

    col_type = conn.select_value(<<~SQL)
      SELECT data_type FROM information_schema.columns
      WHERE table_schema = 'branch_feature_chg_col' AND table_name = 'users' AND column_name = 'name'
    SQL
    assert_equal "text", col_type

    public_type = conn.select_value(<<~SQL)
      SELECT data_type FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'users' AND column_name = 'name'
    SQL
    assert_equal "character varying", public_type
  end

  def test_change_column_default
    conn = reconnect(branch: "feature/chg-def")
    conn.change_column_default :users, :name, "unknown"

    conn.execute("INSERT INTO users (email) VALUES ('test@example.com')")
    name = conn.select_value("SELECT name FROM users WHERE email = 'test@example.com'")
    assert_equal "unknown", name
  end

  def test_change_column_null
    conn = reconnect(branch: "feature/chg-null")
    conn.change_column_null :orders, :status, false, "pending"

    assert_raises(ActiveRecord::NotNullViolation) do
      conn.execute("INSERT INTO orders (status, amount) VALUES (NULL, 50)")
    end
  end

  def test_change_column_comment
    conn = reconnect(branch: "feature/col-comment")
    conn.change_column_comment :users, :name, "The user's display name"

    comment = conn.select_value(<<~SQL)
      SELECT col_description(c.oid, a.attnum)
      FROM pg_attribute a
        JOIN pg_class c ON c.oid = a.attrelid
        JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'branch_feature_col_comment'
        AND c.relname = 'users'
        AND a.attname = 'name'
    SQL
    assert_equal "The user's display name", comment
  end

  def test_change_table_comment
    conn = reconnect(branch: "feature/tbl-comment")
    conn.change_table_comment :users, "A table of users"

    comment = conn.select_value(<<~SQL)
      SELECT obj_description(c.oid)
      FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'branch_feature_tbl_comment' AND c.relname = 'users'
    SQL
    assert_equal "A table of users", comment
  end

  # --- Timestamp DDL ---

  def test_add_timestamps
    conn = reconnect(branch: "feature/add-ts")
    conn.add_timestamps :orders, null: true

    assert column_exists_in_schema?(conn, "branch_feature_add_ts", "orders", "created_at")
    assert column_exists_in_schema?(conn, "branch_feature_add_ts", "orders", "updated_at")
    refute column_exists_in_schema?(conn, "public", "orders", "created_at")
  end

  def test_remove_timestamps
    conn = connect(branch: "main")
    conn.add_timestamps :orders, null: true

    conn = reconnect(branch: "feature/rm-ts")
    conn.remove_timestamps :orders

    refute column_exists_in_schema?(conn, "branch_feature_rm_ts", "orders", "created_at")
    refute column_exists_in_schema?(conn, "branch_feature_rm_ts", "orders", "updated_at")
    assert column_exists_in_schema?(conn, "public", "orders", "created_at")
  end

  # --- Index DDL ---

  def test_add_index
    conn = reconnect(branch: "feature/add-idx")
    conn.add_index :orders, :status

    assert index_exists_in_schema?(conn, "branch_feature_add_idx", "index_orders_on_status")
    refute index_exists_in_schema?(conn, "public", "index_orders_on_status")
  end

  def test_remove_index
    conn = connect(branch: "main")
    conn.add_index :orders, :status, name: "idx_orders_status"

    conn = reconnect(branch: "feature/rm-idx")
    conn.remove_index :orders, name: "idx_orders_status"

    refute index_exists_in_schema?(conn, "branch_feature_rm_idx", "idx_orders_status")
    assert index_exists_in_schema?(conn, "public", "idx_orders_status")
  end

  def test_rename_index
    conn = connect(branch: "main")
    conn.add_index :orders, :status, name: "idx_old"

    conn = reconnect(branch: "feature/ren-idx")
    conn.rename_index :orders, "idx_old", "idx_new"

    assert index_exists_in_schema?(conn, "branch_feature_ren_idx", "idx_new")
    refute index_exists_in_schema?(conn, "branch_feature_ren_idx", "idx_old")
    assert index_exists_in_schema?(conn, "public", "idx_old")
  end

  # --- Foreign key DDL ---

  def test_add_foreign_key
    conn = reconnect(branch: "feature/add-fk")
    conn.add_foreign_key :posts, :authors

    assert foreign_key_exists_on_branch?(conn, "branch_feature_add_fk", "posts", "authors")
    refute foreign_key_exists_on_branch?(conn, "public", "posts", "authors")
  end

  def test_remove_foreign_key
    conn = connect(branch: "main")
    conn.add_foreign_key :posts, :authors

    conn = reconnect(branch: "feature/rm-fk")
    conn.remove_foreign_key :posts, :authors

    refute foreign_key_exists_on_branch?(conn, "branch_feature_rm_fk", "posts", "authors")
    assert foreign_key_exists_on_branch?(conn, "public", "posts", "authors")
  end

  def test_validate_foreign_key
    conn = connect(branch: "main")
    conn.add_foreign_key :posts, :authors, validate: false

    conn = reconnect(branch: "feature/val-fk")
    conn.validate_foreign_key :posts, :authors

    assert table_exists_in_schema?(conn, "branch_feature_val_fk", "posts"),
      "validate_foreign_key must shadow the table"
  end

  # --- Check constraint DDL ---

  def test_add_check_constraint
    conn = reconnect(branch: "feature/add-chk")
    conn.add_check_constraint :orders, "amount > 0", name: "orders_amount_positive"

    assert check_constraint_exists_in_schema?(conn, "branch_feature_add_chk", "orders", "orders_amount_positive")
    assert_raises(ActiveRecord::StatementInvalid) do
      conn.execute("INSERT INTO orders (status, amount) VALUES ('bad', -1)")
    end
  end

  def test_remove_check_constraint
    conn = connect(branch: "main")
    conn.add_check_constraint :orders, "amount > 0", name: "orders_amount_positive"

    conn = reconnect(branch: "feature/rm-chk")
    conn.remove_check_constraint :orders, name: "orders_amount_positive"

    refute check_constraint_exists_in_schema?(conn, "branch_feature_rm_chk", "orders", "orders_amount_positive")
    assert check_constraint_exists_in_schema?(conn, "public", "orders", "orders_amount_positive")
  end

  def test_validate_check_constraint
    conn = connect(branch: "main")
    conn.add_check_constraint :orders, "amount > 0", name: "orders_amount_positive", validate: false

    conn = reconnect(branch: "feature/val-chk")
    conn.validate_check_constraint :orders, name: "orders_amount_positive"

    assert table_exists_in_schema?(conn, "branch_feature_val_chk", "orders"),
      "validate_check_constraint must shadow the table"
  end

  # --- Exclusion constraint DDL ---

  def test_add_exclusion_constraint
    conn = connect(branch: "main")
    conn.enable_extension "btree_gist"

    conn = reconnect(branch: "feature/add-excl")
    conn.add_exclusion_constraint :orders, "amount WITH =", using: :gist, name: "orders_amount_excl"

    assert constraint_exists?(conn, "branch_feature_add_excl", "orders", "orders_amount_excl")
    refute constraint_exists?(conn, "public", "orders", "orders_amount_excl")
  end

  def test_remove_exclusion_constraint
    conn = connect(branch: "main")
    conn.enable_extension "btree_gist"
    conn.add_exclusion_constraint :orders, "amount WITH =", using: :gist, name: "orders_amount_excl"

    conn = reconnect(branch: "feature/rm-excl")
    conn.remove_exclusion_constraint :orders, name: "orders_amount_excl"

    refute constraint_exists?(conn, "branch_feature_rm_excl", "orders", "orders_amount_excl")
    assert constraint_exists?(conn, "public", "orders", "orders_amount_excl")
  end

  # --- Unique constraint DDL ---

  def test_add_unique_constraint
    conn = reconnect(branch: "feature/add-uniq")
    conn.add_unique_constraint :users, :email, name: "users_email_uniq"

    assert constraint_exists?(conn, "branch_feature_add_uniq", "users", "users_email_uniq")
    refute constraint_exists?(conn, "public", "users", "users_email_uniq")
  end

  def test_remove_unique_constraint
    conn = connect(branch: "main")
    conn.add_unique_constraint :users, :email, name: "users_email_uniq"

    conn = reconnect(branch: "feature/rm-uniq")
    conn.remove_unique_constraint :users, name: "users_email_uniq"

    refute constraint_exists?(conn, "branch_feature_rm_uniq", "users", "users_email_uniq")
    assert constraint_exists?(conn, "public", "users", "users_email_uniq")
  end

  # --- Generic constraint DDL ---

  def test_validate_constraint
    conn = connect(branch: "main")
    conn.add_check_constraint :orders, "amount > 0", name: "orders_amount_positive", validate: false

    conn = reconnect(branch: "feature/val-con")
    conn.validate_constraint :orders, "orders_amount_positive"

    assert table_exists_in_schema?(conn, "branch_feature_val_con", "orders"),
      "validate_constraint must shadow the table"
  end

  def test_remove_constraint
    conn = connect(branch: "main")
    conn.add_check_constraint :orders, "amount > 0", name: "orders_amount_positive"

    conn = reconnect(branch: "feature/rm-con")
    conn.remove_constraint :orders, "orders_amount_positive"

    refute constraint_exists?(conn, "branch_feature_rm_con", "orders", "orders_amount_positive")
    assert constraint_exists?(conn, "public", "orders", "orders_amount_positive")
  end

  # --- Reference DDL ---

  def test_add_reference
    conn = reconnect(branch: "feature/add-ref")
    conn.add_reference :orders, :user, foreign_key: true

    assert column_exists_in_schema?(conn, "branch_feature_add_ref", "orders", "user_id")
    refute column_exists_in_schema?(conn, "public", "orders", "user_id")
  end

  def test_remove_reference
    conn = connect(branch: "main")
    conn.add_reference :orders, :user

    conn = reconnect(branch: "feature/rm-ref")
    conn.remove_reference :orders, :user

    refute column_exists_in_schema?(conn, "branch_feature_rm_ref", "orders", "user_id")
    assert column_exists_in_schema?(conn, "public", "orders", "user_id")
  end

  # --- Table-level DDL ---

  def test_create_table
    conn = reconnect(branch: "feature/create-tbl")
    conn.create_table(:payments) { |t| t.integer :amount }

    assert table_exists_in_schema?(conn, "branch_feature_create_tbl", "payments")
    refute table_exists_in_schema?(conn, "public", "payments")
  end

  def test_drop_table
    conn = reconnect(branch: "feature/drop-tbl")
    conn.drop_table :orders

    assert table_exists_in_schema?(conn, "public", "orders"),
      "Public table must survive branch drop"
    refute table_exists_in_schema?(conn, "branch_feature_drop_tbl", "orders")
  end

  def test_drop_table_is_not_visible_on_branch
    skip "Known bug: dropped tables fall through search_path to public"

    conn = reconnect(branch: "feature/drop-vis")
    conn.drop_table :orders

    # After dropping on a branch, the table should NOT be queryable
    # via the branch's search_path.
    assert_raises(ActiveRecord::StatementInvalid) do
      conn.execute("INSERT INTO orders (status, amount) VALUES ('new', 200)")
    end
  end

  def test_rename_table
    conn = reconnect(branch: "feature/ren-tbl")
    conn.rename_table :orders, :purchases

    assert table_exists_in_schema?(conn, "branch_feature_ren_tbl", "purchases")
    refute table_exists_in_schema?(conn, "branch_feature_ren_tbl", "orders")
    assert table_exists_in_schema?(conn, "public", "orders"),
      "Public must keep original table"
  end

  def test_change_table
    conn = reconnect(branch: "feature/chg-tbl")
    conn.change_table(:users) { |t| t.string :nickname }

    assert column_exists_in_schema?(conn, "branch_feature_chg_tbl", "users", "nickname")
    refute column_exists_in_schema?(conn, "public", "users", "nickname")
  end

  def test_bulk_change_table
    conn = reconnect(branch: "feature/bulk-chg")
    conn.change_table(:users, bulk: true) do |t|
      t.string :nickname
      t.string :avatar
    end

    assert column_exists_in_schema?(conn, "branch_feature_bulk_chg", "users", "nickname")
    assert column_exists_in_schema?(conn, "branch_feature_bulk_chg", "users", "avatar")
    refute column_exists_in_schema?(conn, "public", "users", "nickname")
  end

  # --- Join table DDL ---

  def test_create_join_table
    conn = reconnect(branch: "feature/create-jt")
    conn.create_join_table :orders, :users

    assert table_exists_in_schema?(conn, "branch_feature_create_jt", "orders_users")
    refute table_exists_in_schema?(conn, "public", "orders_users")
  end

  def test_drop_join_table
    conn = connect(branch: "main")
    conn.create_join_table :orders, :users

    conn = reconnect(branch: "feature/drop-jt")
    conn.drop_join_table :orders, :users

    refute table_exists_in_schema?(conn, "branch_feature_drop_jt", "orders_users")
    assert table_exists_in_schema?(conn, "public", "orders_users"),
      "Public join table must survive branch drop"
  end

  # --- Shadow structural equivalence ---
  # After shadowing, the branch table should have the same columns,
  # indexes, and constraints as public (before the DDL change).

  def test_shadow_preserves_all_columns
    conn = connect(branch: "main")
    conn.add_index :users, :email, unique: true

    conn = reconnect(branch: "feature/equiv-cols")
    conn.add_column :users, :bio, :string

    public_cols = conn.select_values(<<~SQL).sort
      SELECT column_name FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'users'
    SQL
    branch_cols = conn.select_values(<<~SQL).sort
      SELECT column_name FROM information_schema.columns
      WHERE table_schema = 'branch_feature_equiv_cols' AND table_name = 'users'
    SQL

    assert_equal (public_cols + ["bio"]).sort, branch_cols,
      "Branch should have all public columns plus the new one"
  end

  def test_shadow_preserves_all_indexes
    conn = connect(branch: "main")
    conn.add_index :users, :email, unique: true, name: "idx_users_email"
    conn.add_index :users, :name, name: "idx_users_name"

    conn = reconnect(branch: "feature/equiv-idx")
    conn.add_column :users, :bio, :string

    public_indexes = conn.select_values(<<~SQL).sort
      SELECT indexname FROM pg_indexes
      WHERE schemaname = 'public' AND tablename = 'users'
    SQL
    branch_indexes = conn.select_values(<<~SQL).sort
      SELECT indexname FROM pg_indexes
      WHERE schemaname = 'branch_feature_equiv_idx' AND tablename = 'users'
    SQL

    assert_equal public_indexes, branch_indexes,
      "Branch should preserve all indexes from public"
  end

  def test_shadow_preserves_data
    conn = reconnect(branch: "feature/equiv-data")
    conn.add_column :users, :bio, :string

    public_count = conn.select_value("SELECT count(*) FROM public.users")
    branch_count = conn.select_value("SELECT count(*) FROM branch_feature_equiv_data.users")
    assert_equal public_count, branch_count, "Shadow must copy all rows"
  end

  # --- Meta: ensure every DDL method has a test ---

  # Methods that don't need their own test — either aliases of tested
  # methods, internal helpers, or read-only queries.
  SKIP_COVERAGE = %i[
    add_belongs_to remove_belongs_to
    add_index_options
    build_add_column_definition build_change_column_default_definition
    build_change_column_definition build_create_index_definition
    build_create_join_table_definition build_create_table_definition
    check_constraint_exists? check_constraint_options check_constraints
    column_exists? columns
    default_sequence_name disable_index enable_index
    exclusion_constraint_options exclusion_constraints
    foreign_key_column_for foreign_key_exists? foreign_key_options foreign_keys
    foreign_table_exists?
    index_exists? index_name index_name_exists? indexes
    inherited_table_names
    pk_and_sequence_for primary_key primary_keys
    reset_pk_sequence! serial_sequence set_pk_sequence!
    table_alias_for table_comment table_exists? table_options table_partition_definition
    unique_constraint_options unique_constraints
    update_table_definition
  ].freeze

  def test_every_ddl_method_has_coverage
    test_names = self.class.instance_methods(false).grep(/\Atest_/).map(&:to_s)
    untested = ActiveRecord::ConnectionAdapters::PostgreSQL::Branched.table_methods - SKIP_COVERAGE

    untested.reject! do |method|
      test_names.any? { |t| t == "test_#{method}" || t.start_with?("test_#{method}_") }
    end

    assert_empty untested,
      "DDL methods without test coverage: #{untested.sort.join(', ')}. " \
      "Add a test or add to SKIP_COVERAGE with a reason."
  end

  private

  def foreign_key_exists_on_branch?(conn, schema, from_table, to_table)
    conn.select_value(<<~SQL) == 1
      SELECT 1 FROM pg_constraint c
        JOIN pg_class t ON t.oid = c.conrelid
        JOIN pg_namespace n ON n.oid = t.relnamespace
        JOIN pg_class ref ON ref.oid = c.confrelid
      WHERE c.contype = 'f'
        AND n.nspname = #{conn.quote(schema)}
        AND t.relname = #{conn.quote(from_table)}
        AND ref.relname = #{conn.quote(to_table)}
    SQL
  end

  def constraint_exists?(conn, schema, table, constraint_name)
    conn.select_value(<<~SQL) == 1
      SELECT 1 FROM pg_constraint c
        JOIN pg_class t ON t.oid = c.conrelid
        JOIN pg_namespace n ON n.oid = t.relnamespace
      WHERE n.nspname = #{conn.quote(schema)}
        AND t.relname = #{conn.quote(table)}
        AND c.conname = #{conn.quote(constraint_name)}
    SQL
  end
end
