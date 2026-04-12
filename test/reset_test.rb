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
    conn = connect(branch_override: "feature/reset-me")

    conn.execute("CREATE TABLE public.users (id serial PRIMARY KEY, name varchar)")
    conn.execute("INSERT INTO public.users (name) VALUES ('alice')")

    conn.add_column :users, :bio, :string
    assert table_exists_in_schema?(conn, "pgb_feature_reset_me", "users")

    # Simulate db:branch:reset
    conn.execute("DROP SCHEMA pgb_feature_reset_me CASCADE")
    conn.execute("CREATE SCHEMA pgb_feature_reset_me")
    conn.execute("SET search_path TO pgb_feature_reset_me, public")

    # Should fall through to public now
    refute column_exists_in_schema?(conn, "pgb_feature_reset_me", "users", "bio")

    result = conn.select_value("SELECT name FROM users LIMIT 1")
    assert_equal "alice", result, "Should read from public after reset"
  end

  def test_discard_drops_schema_entirely
    conn = connect(branch_override: "feature/discard-me")

    conn.execute("CREATE TABLE pgb_feature_discard_me.stale (id serial)")
    assert schema_exists?(conn, "pgb_feature_discard_me")

    conn.execute("DROP SCHEMA pgb_feature_discard_me CASCADE")
    refute schema_exists?(conn, "pgb_feature_discard_me")
  end
end
