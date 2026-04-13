require "test_helper"

class ResetTest < Minitest::Test
  include PGBTestSupport

  def setup
    setup_test_database
  end

  def teardown
    teardown_test_database
  end

  def test_reset_clears_shadow_and_falls_through_to_public
    main_conn = connect(branch: "main")
    main_conn.create_table(:users) { |t| t.string :name }
    main_conn.execute("INSERT INTO users (name) VALUES ('alice')")

    feature_conn = reconnect(branch: "feature/reset-me")
    feature_conn.add_column :users, :bio, :string
    assert table_exists_in_schema?(feature_conn, "branch_feature_reset_me", "users")

    feature_conn.branch_manager.reset

    refute column_exists_in_schema?(feature_conn, "branch_feature_reset_me", "users", "bio")
    result = feature_conn.select_value("SELECT name FROM users LIMIT 1")
    assert_equal "alice", result, "Should fall through to public after reset"
  end

  def test_discard_drops_schema_entirely
    conn = connect(branch: "feature/discard-me")
    conn.execute("CREATE TABLE branch_feature_discard_me.stale (id serial)")
    assert schema_exists?(conn, "branch_feature_discard_me")

    conn.branch_manager.discard
    refute schema_exists?(conn, "branch_feature_discard_me")
  end
end
