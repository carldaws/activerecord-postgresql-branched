require "test_helper"

class AdapterTest < Minitest::Test
  include PGBTestSupport

  def setup
    setup_test_database
  end

  def teardown
    teardown_test_database
  end

  def test_creates_branch_schema_on_connect
    conn = connect(branch_override: "feature/payments")
    assert schema_exists?(conn, "branch_feature_payments"),
      "Expected branch schema branch_feature_payments to exist"
  end

  def test_sets_search_path_to_branch_and_public
    conn = connect(branch_override: "feature/payments")
    search_path = conn.select_value("SHOW search_path")
    assert_equal "branch_feature_payments, public", search_path
  end

  def test_primary_branch_does_not_create_schema
    conn = connect(branch_override: "main")
    refute schema_exists?(conn, "branch_main"),
      "Expected branch_main schema NOT to be created on primary branch"
  end

  def test_primary_branch_leaves_search_path_alone
    conn = connect(branch_override: "main")
    search_path = conn.select_value("SHOW search_path")
    # Should NOT contain branch_main
    refute_includes search_path, "branch_main"
  end

  def test_custom_primary_branch
    conn = connect(branch_override: "trunk", primary_branch: "trunk")
    refute schema_exists?(conn, "branch_trunk"),
      "Expected branch_trunk schema NOT to be created when trunk is primary"
  end

  def test_branch_override_via_config
    conn = connect(branch_override: "agent-0")
    assert schema_exists?(conn, "branch_agent_0")
    search_path = conn.select_value("SHOW search_path")
    assert_equal "branch_agent_0, public", search_path
  end

  def test_branch_table_takes_precedence_over_public
    conn = connect(branch_override: "feature/test")

    conn.execute("CREATE TABLE public.widgets (id serial PRIMARY KEY, name varchar)")
    conn.execute("INSERT INTO public.widgets (name) VALUES ('public_widget')")

    conn.execute("CREATE TABLE branch_feature_test.widgets (id serial PRIMARY KEY, name varchar, extra varchar)")
    conn.execute("INSERT INTO branch_feature_test.widgets (name, extra) VALUES ('branch_widget', 'bonus')")

    result = conn.select_value("SELECT name FROM widgets LIMIT 1")
    assert_equal "branch_widget", result
  end

  def test_fallthrough_to_public
    conn = connect(branch_override: "feature/test")

    conn.execute("CREATE TABLE public.products (id serial PRIMARY KEY, title varchar)")
    conn.execute("INSERT INTO public.products (title) VALUES ('from_public')")

    result = conn.select_value("SELECT title FROM products LIMIT 1")
    assert_equal "from_public", result
  end

  def test_schema_migrations_isolated_per_branch
    # Set up public schema_migrations with a baseline timestamp
    main_conn = connect(branch_override: "main")
    main_conn.execute(<<~SQL)
      CREATE TABLE public.schema_migrations (version varchar NOT NULL PRIMARY KEY)
    SQL
    main_conn.execute("INSERT INTO public.schema_migrations (version) VALUES ('20260101000000')")
    ActiveRecord::Base.connection_pool.disconnect!

    # Connect on a feature branch — schema_migrations should be shadowed
    branch_conn = connect(branch_override: "feature/isolated")
    assert table_exists_in_schema?(branch_conn, "branch_feature_isolated", "schema_migrations"),
      "schema_migrations should be shadowed into branch schema"

    # Branch migration adds its own timestamp
    branch_conn.execute("INSERT INTO schema_migrations (version) VALUES ('20260401000000')")

    # Branch sees both timestamps
    branch_versions = branch_conn.select_values("SELECT version FROM schema_migrations ORDER BY version")
    assert_equal %w[20260101000000 20260401000000], branch_versions

    # Public only has the original
    public_versions = branch_conn.select_values("SELECT version FROM public.schema_migrations ORDER BY version")
    assert_equal %w[20260101000000], public_versions
  end
end
