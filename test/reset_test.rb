require "test_helper"

class ResetTest < Minitest::Test
  include PGBTestSupport

  def setup
    setup_test_database
  end

  def teardown
    teardown_test_database
  end

  def test_dropping_branch_schema_resets_to_public
    conn = connect(branch: "feature/reset-me")

    conn.execute("CREATE TABLE public.users (id serial PRIMARY KEY, name varchar)")
    conn.execute("INSERT INTO public.users (name) VALUES ('alice')")

    conn.add_column :users, :bio, :string
    assert table_exists_in_schema?(conn, "branch_feature_reset_me", "users")

    conn.branch_manager.reset

    refute column_exists_in_schema?(conn, "branch_feature_reset_me", "users", "bio")

    result = conn.select_value("SELECT name FROM users LIMIT 1")
    assert_equal "alice", result, "Should read from public after reset"
  end

  def test_discard_drops_schema_entirely
    conn = connect(branch: "feature/discard-me")

    conn.execute("CREATE TABLE branch_feature_discard_me.stale (id serial)")
    assert schema_exists?(conn, "branch_feature_discard_me")

    conn.branch_manager.discard
    refute schema_exists?(conn, "branch_feature_discard_me")
  end
end
