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

  def test_sanitise_very_long_branch_name
    long_name = "feature/" + "a" * 200
    schema = BranchManager.sanitise(long_name)
    assert schema.start_with?("branch_feature_")
    assert_equal "branch_feature_" + "a" * 200, schema
  end

  def test_empty_branch_raises
    setup_test_database
    connect(branch_override: "main")
    ActiveRecord::Base.connection_pool.disconnect!

    error = assert_raises(RuntimeError) do
      ActiveRecord::Base.establish_connection(
        adapter: "postgresql_branched",
        database: DATABASE_NAME,
        branch_override: ""
      )
      ActiveRecord::Base.lease_connection
    end
    assert_match(/Could not determine git branch/, error.message)
  ensure
    teardown_test_database
  end

  def test_resolve_branch_prefers_config_override
    config = { branch_override: "from-config" }
    assert_equal "from-config", BranchManager.resolve_branch_name(config)
  end

  def test_resolve_branch_falls_back_to_env
    ENV["PGBRANCH"] = "from-env"
    config = {}
    assert_equal "from-env", BranchManager.resolve_branch_name(config)
  ensure
    ENV.delete("PGBRANCH")
  end

  def test_resolve_branch_env_branch_takes_precedence_over_pgbranch
    ENV["BRANCH"] = "from-branch-env"
    ENV["PGBRANCH"] = "from-pgbranch-env"
    config = {}
    assert_equal "from-branch-env", BranchManager.resolve_branch_name(config)
  ensure
    ENV.delete("BRANCH")
    ENV.delete("PGBRANCH")
  end

  def test_reset_drops_and_recreates_schema
    setup_test_database
    conn = connect(branch_override: "feature/reset-test")
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
    conn = connect(branch_override: "feature/discard-test")
    manager = conn.branch_manager

    assert schema_exists?(conn, "branch_feature_discard_test")

    manager.discard
    refute schema_exists?(conn, "branch_feature_discard_test")
  ensure
    teardown_test_database
  end

  def test_discard_prevents_dropping_primary_branch
    setup_test_database
    conn = connect(branch_override: "feature/safe")
    manager = conn.branch_manager

    error = assert_raises(RuntimeError) { manager.discard("main") }
    assert_match(/Cannot discard the primary branch/, error.message)
  ensure
    teardown_test_database
  end

  def test_list_returns_branch_schemas
    setup_test_database
    conn = connect(branch_override: "feature/listed")
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
    conn = connect(branch_override: "feature/diffed")
    manager = conn.branch_manager

    conn.create_table(:widgets) { |t| t.string :name }
    tables = manager.diff

    assert_includes tables, "widgets"
  ensure
    teardown_test_database
  end

  def test_diff_returns_empty_on_primary_branch
    setup_test_database
    conn = connect(branch_override: "main")
    manager = conn.branch_manager

    assert_equal [], manager.diff
  ensure
    teardown_test_database
  end
end
