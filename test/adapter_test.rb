require "test_helper"

class AdapterTest < Minitest::Test
  include PGBTestSupport

  def setup
    setup_test_database
  end

  def teardown
    teardown_test_database
  end

  # --- Primary branch behavior ---

  def test_primary_branch_does_not_create_schema
    conn = connect(branch: "main")
    refute schema_exists?(conn, "branch_main"),
      "Primary branch must NOT create a branch schema"
  end

  def test_primary_branch_leaves_search_path_default
    conn = connect(branch: "main")
    search_path = conn.select_value("SHOW search_path")
    refute_includes search_path, "branch_main",
      "Primary branch search_path must not reference a branch schema"
  end

  def test_primary_branch_writes_to_public
    conn = connect(branch: "main")
    conn.create_table(:users) { |t| t.string :name }

    assert table_exists_in_schema?(conn, "public", "users"),
      "Primary branch must write tables to public"
  end

  def test_primary_branch_ddl_modifies_public_directly
    conn = connect(branch: "main")
    conn.create_table(:users) { |t| t.string :name }
    conn.add_column :users, :email, :string

    assert column_exists_in_schema?(conn, "public", "users", "email"),
      "DDL on primary branch must modify public directly"
  end

  # --- Feature branch behavior ---

  def test_feature_branch_creates_schema
    conn = connect(branch: "feature/payments")
    assert schema_exists?(conn, "branch_feature_payments")
  end

  def test_feature_branch_sets_search_path
    conn = connect(branch: "feature/payments")
    search_path = conn.select_value("SHOW search_path")
    assert_equal "branch_feature_payments, public", search_path
  end

  def test_feature_branch_table_takes_precedence_over_public
    conn = connect(branch: "main")
    conn.execute("CREATE TABLE public.widgets (id serial PRIMARY KEY, name varchar)")
    conn.execute("INSERT INTO public.widgets (name) VALUES ('public_widget')")

    feature_conn = reconnect(branch: "feature/test")
    feature_conn.execute("CREATE TABLE branch_feature_test.widgets (id serial PRIMARY KEY, name varchar, extra varchar)")
    feature_conn.execute("INSERT INTO branch_feature_test.widgets (name, extra) VALUES ('branch_widget', 'bonus')")

    result = feature_conn.select_value("SELECT name FROM widgets LIMIT 1")
    assert_equal "branch_widget", result
  end

  def test_feature_branch_falls_through_to_public
    conn = connect(branch: "main")
    conn.execute("CREATE TABLE public.products (id serial PRIMARY KEY, title varchar)")
    conn.execute("INSERT INTO public.products (title) VALUES ('from_public')")

    feature_conn = reconnect(branch: "feature/test")
    result = feature_conn.select_value("SELECT title FROM products LIMIT 1")
    assert_equal "from_public", result
  end

  def test_schema_migrations_isolated_per_branch
    main_conn = connect(branch: "main")
    main_conn.execute("CREATE TABLE public.schema_migrations (version varchar NOT NULL PRIMARY KEY)")
    main_conn.execute("INSERT INTO public.schema_migrations (version) VALUES ('20260101000000')")

    branch_conn = reconnect(branch: "feature/isolated")
    assert table_exists_in_schema?(branch_conn, "branch_feature_isolated", "schema_migrations"),
      "schema_migrations should be shadowed into branch schema"

    branch_conn.execute("INSERT INTO schema_migrations (version) VALUES ('20260401000000')")

    branch_versions = branch_conn.select_values("SELECT version FROM schema_migrations ORDER BY version")
    assert_equal %w[20260101000000 20260401000000], branch_versions

    public_versions = branch_conn.select_values("SELECT version FROM public.schema_migrations ORDER BY version")
    assert_equal %w[20260101000000], public_versions
  end

  def test_ar_internal_metadata_isolated_per_branch
    main_conn = connect(branch: "main")
    main_conn.execute("CREATE TABLE public.ar_internal_metadata (key varchar NOT NULL PRIMARY KEY, value varchar)")
    main_conn.execute("INSERT INTO public.ar_internal_metadata (key, value) VALUES ('environment', 'development')")

    branch_conn = reconnect(branch: "feature/meta")
    assert table_exists_in_schema?(branch_conn, "branch_feature_meta", "ar_internal_metadata")

    branch_conn.execute("UPDATE ar_internal_metadata SET value = 'test' WHERE key = 'environment'")

    assert_equal "test", branch_conn.select_value("SELECT value FROM ar_internal_metadata WHERE key = 'environment'")
    assert_equal "development", branch_conn.select_value("SELECT value FROM public.ar_internal_metadata WHERE key = 'environment'")
  end

  def test_cross_branch_isolation
    conn_a = connect(branch: "feature/alpha")
    conn_a.create_table(:alpha_things) { |t| t.string :name }

    conn_b = reconnect(branch: "feature/bravo")
    conn_b.create_table(:bravo_things) { |t| t.string :name }

    refute table_exists_in_schema?(conn_b, "branch_feature_bravo", "alpha_things")
    refute table_exists_in_schema?(conn_b, "public", "alpha_things")
  end
end
