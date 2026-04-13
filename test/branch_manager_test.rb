require "test_helper"

class BranchManagerTest < Minitest::Test
  include PGBTestSupport

  BranchManager = ActiveRecord::ConnectionAdapters::PostgreSQL::Branched::BranchManager

  def test_sanitise_simple_branch
    assert_equal "branch_main", BranchManager.sanitise("main")
  end

  def test_sanitise_slash
    assert_equal "branch_feature_payments", BranchManager.sanitise("feature/payments")
  end

  def test_sanitise_dash
    assert_equal "branch_fix_user_auth", BranchManager.sanitise("fix/user-auth")
  end

  def test_sanitise_dots
    assert_equal "branch_release_2_4_0", BranchManager.sanitise("release/2.4.0")
  end

  def test_sanitise_mixed
    assert_equal "branch_agent_007", BranchManager.sanitise("agent-007")
  end

  def test_sanitise_uppercase
    assert_equal "branch_feature_loud", BranchManager.sanitise("FEATURE/LOUD")
  end

  def test_sanitise_strips_non_alphanumeric
    assert_equal "branch_weirdbranch", BranchManager.sanitise("weird!@#branch")
  end

  def test_sanitise_truncates_long_branch_names
    long_name = "feature/" + "a" * 200
    schema = BranchManager.sanitise(long_name)
    assert_operator schema.bytesize, :<=, 63
    assert schema.start_with?("branch_feature_")
  end

  def test_sanitise_long_names_with_different_suffixes_do_not_collide
    base = "a" * 200
    schema_a = BranchManager.sanitise(base + "_alpha")
    schema_b = BranchManager.sanitise(base + "_bravo")
    refute_equal schema_a, schema_b, "Different long branches must produce different schema names"
  end

  def test_sanitise_short_names_are_not_truncated
    schema = BranchManager.sanitise("feature/short")
    assert_equal "branch_feature_short", schema
  end

  def test_empty_branch_raises
    setup_test_database
    connect(branch: "anything")
    ActiveRecord::Base.connection_pool.disconnect!

    ENV["PGBRANCH"] = ""
    error = assert_raises(RuntimeError) do
      ActiveRecord::Base.establish_connection(
        adapter: "postgresql_branched",
        database: DATABASE_NAME
      )
      ActiveRecord::Base.lease_connection
    end
    assert_match(/Could not determine branch/, error.message)
  ensure
    teardown_test_database
  end

  def test_resolve_branch_from_pgbranch_env
    ENV["PGBRANCH"] = "from-env"
    assert_equal "from-env", BranchManager.resolve_branch_name
  ensure
    ENV.delete("PGBRANCH")
  end

  def test_reset_drops_and_recreates_schema
    setup_test_database
    conn = connect(branch: "feature/reset-test")
    manager = conn.branch_manager

    conn.create_table(:widgets) { |t| t.string :name }
    assert table_exists_in_schema?(conn, "branch_feature_reset_test", "widgets")

    manager.reset

    refute table_exists_in_schema?(conn, "branch_feature_reset_test", "widgets")
    assert schema_exists?(conn, "branch_feature_reset_test")
  ensure
    teardown_test_database
  end

  def test_discard_drops_schema
    setup_test_database
    conn = connect(branch: "feature/discard-test")
    manager = conn.branch_manager

    assert schema_exists?(conn, "branch_feature_discard_test")

    manager.discard
    refute schema_exists?(conn, "branch_feature_discard_test")
  ensure
    teardown_test_database
  end

  def test_discard_other_branch_by_name
    setup_test_database
    conn = connect(branch: "feature/active")

    # Create another branch schema manually
    conn.execute("CREATE SCHEMA IF NOT EXISTS branch_feature_stale")
    assert schema_exists?(conn, "branch_feature_stale")

    conn.branch_manager.discard("feature/stale")
    refute schema_exists?(conn, "branch_feature_stale")
  ensure
    teardown_test_database
  end

  def test_list_returns_branch_schemas
    setup_test_database
    conn = connect(branch: "feature/listed")
    manager = conn.branch_manager

    conn.create_table(:widgets) { |t| t.string :name }
    rows = manager.list

    schema_names = rows.map(&:first)
    assert_includes schema_names, "branch_feature_listed"
  ensure
    teardown_test_database
  end

  def test_diff_returns_branch_local_tables
    setup_test_database
    conn = connect(branch: "feature/diffed")
    manager = conn.branch_manager

    conn.create_table(:widgets) { |t| t.string :name }
    tables = manager.diff

    assert_includes tables, "widgets"
  ensure
    teardown_test_database
  end

  def test_list_works_with_empty_schema
    setup_test_database
    conn = connect(branch: "feature/empty")
    manager = conn.branch_manager

    rows = manager.list
    schema_names = rows.map(&:first)
    assert_includes schema_names, "branch_feature_empty"
  ensure
    teardown_test_database
  end

  def test_prune_drops_schemas_not_in_keep_list
    setup_test_database
    conn = connect(branch: "feature/keeper")

    conn.execute("CREATE SCHEMA IF NOT EXISTS branch_feature_stale_one")
    conn.execute("CREATE SCHEMA IF NOT EXISTS branch_feature_stale_two")

    assert schema_exists?(conn, "branch_feature_stale_one")
    assert schema_exists?(conn, "branch_feature_stale_two")

    pruned = conn.branch_manager.prune(keep: ["feature/keeper"])

    assert_includes pruned, "branch_feature_stale_one"
    assert_includes pruned, "branch_feature_stale_two"
    refute schema_exists?(conn, "branch_feature_stale_one")
    refute schema_exists?(conn, "branch_feature_stale_two")
    assert schema_exists?(conn, "branch_feature_keeper"), "Kept branch schema should still exist"
  ensure
    teardown_test_database
  end

  def test_prune_preserves_kept_schemas
    setup_test_database
    conn = connect(branch: "feature/a")
    ActiveRecord::Base.connection_pool.disconnect!

    conn = connect(branch: "feature/b")
    conn.execute("CREATE SCHEMA IF NOT EXISTS branch_feature_a")

    pruned = conn.branch_manager.prune(keep: %w[feature/a feature/b])

    assert_equal [], pruned
    assert schema_exists?(conn, "branch_feature_a")
    assert schema_exists?(conn, "branch_feature_b")
  ensure
    teardown_test_database
  end
end
