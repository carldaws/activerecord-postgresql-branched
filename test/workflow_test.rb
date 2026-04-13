require "test_helper"

# These tests simulate real developer workflows end-to-end.
# They exercise the interaction between primary and feature branches
# across connection cycles, which is where the adapter's value lies.
class WorkflowTest < Minitest::Test
  include PGBTestSupport

  def setup
    setup_test_database
  end

  def teardown
    teardown_test_database
  end

  # The core contract: tables created on main land in public,
  # and feature branches see them via search_path fallthrough.
  def test_main_creates_in_public_and_feature_branch_sees_via_fallthrough
    main_conn = connect(branch: "main")
    main_conn.create_table(:users) { |t| t.string :name }
    main_conn.execute("INSERT INTO users (name) VALUES ('alice')")

    assert table_exists_in_schema?(main_conn, "public", "users"),
      "Tables created on primary branch must go to public"

    feature_conn = reconnect(branch: "feature/next")

    result = feature_conn.select_value("SELECT name FROM users LIMIT 1")
    assert_equal "alice", result,
      "Feature branch must see primary branch tables via fallthrough"
  end

  # Feature branch tables must NOT leak into public.
  def test_feature_branch_does_not_write_to_public
    main_conn = connect(branch: "main")
    main_conn.create_table(:users) { |t| t.string :name }

    feature_conn = reconnect(branch: "feature/payments")
    feature_conn.create_table(:payments) { |t| t.integer :amount }

    assert table_exists_in_schema?(feature_conn, "branch_feature_payments", "payments"),
      "New table should be in branch schema"
    refute table_exists_in_schema?(feature_conn, "public", "payments"),
      "New table must NOT appear in public"
  end

  # Simulates: PR merged, team pulls main, runs db:migrate, then starts
  # a new feature branch. The new feature branch must see the merged work.
  def test_merged_migration_visible_to_new_feature_branch
    # Initial schema on main
    main_conn = connect(branch: "main")
    main_conn.create_table(:users) { |t| t.string :name }

    # Simulate merged PR: new migration runs on main
    main_conn.create_table(:payments) { |t| t.integer :amount }
    main_conn.add_column :users, :email, :string

    assert table_exists_in_schema?(main_conn, "public", "payments")
    assert column_exists_in_schema?(main_conn, "public", "users", "email")

    # New feature branch should see everything
    feature_conn = reconnect(branch: "feature/next")

    assert_equal "payments", feature_conn.select_value(
      "SELECT table_name FROM information_schema.tables WHERE table_name = 'payments' AND table_schema = 'public'"
    ), "Feature branch should see payments via public fallthrough"

    assert column_exists_in_schema?(feature_conn, "public", "users", "email"),
      "Feature branch should see columns added on main"
  end

  # Simulates: developer modifies a table on a feature branch, then switches
  # back to main. Main's version should be untouched.
  def test_feature_branch_modification_does_not_affect_main
    main_conn = connect(branch: "main")
    main_conn.create_table(:users) { |t| t.string :name }
    main_conn.execute("INSERT INTO users (name) VALUES ('alice')")

    # Feature branch shadows users and adds a column
    feature_conn = reconnect(branch: "feature/profiles")
    feature_conn.add_column :users, :bio, :string

    assert column_exists_in_schema?(feature_conn, "branch_feature_profiles", "users", "bio")

    # Switch back to main
    main_conn = reconnect(branch: "main")

    refute column_exists_in_schema?(main_conn, "public", "users", "bio"),
      "Main should NOT see feature branch's column"

    result = main_conn.select_value("SELECT name FROM users LIMIT 1")
    assert_equal "alice", result, "Main data should be untouched"
  end

  # Simulates: two feature branches work independently on the same table,
  # neither sees the other's changes, and main is untouched.
  def test_two_branches_modify_same_table_independently
    main_conn = connect(branch: "main")
    main_conn.create_table(:users) { |t| t.string :name }
    main_conn.execute("INSERT INTO users (name) VALUES ('alice')")

    # Branch A adds bio
    branch_a = reconnect(branch: "feature/a")
    branch_a.add_column :users, :bio, :string

    # Branch B adds age
    branch_b = reconnect(branch: "feature/b")
    branch_b.add_column :users, :age, :integer

    # Branch A should have bio but not age
    branch_a = reconnect(branch: "feature/a")
    assert column_exists_in_schema?(branch_a, "branch_feature_a", "users", "bio")
    refute column_exists_in_schema?(branch_a, "branch_feature_a", "users", "age")

    # Branch B should have age but not bio
    branch_b = reconnect(branch: "feature/b")
    assert column_exists_in_schema?(branch_b, "branch_feature_b", "users", "age")
    refute column_exists_in_schema?(branch_b, "branch_feature_b", "users", "bio")

    # Main should have neither
    main_conn = reconnect(branch: "main")
    refute column_exists_in_schema?(main_conn, "public", "users", "bio")
    refute column_exists_in_schema?(main_conn, "public", "users", "age")
  end

  # Simulates: db:branch:reset then db:migrate after rebasing.
  # Branch schema is dropped, fallthrough to public resumes, and
  # branch-specific migrations can be reapplied.
  def test_reset_restores_fallthrough_to_public
    main_conn = connect(branch: "main")
    main_conn.create_table(:users) { |t| t.string :name }
    main_conn.execute("INSERT INTO users (name) VALUES ('alice')")

    feature_conn = reconnect(branch: "feature/rebase")
    feature_conn.add_column :users, :bio, :string
    feature_conn.create_table(:payments) { |t| t.integer :amount }

    assert table_exists_in_schema?(feature_conn, "branch_feature_rebase", "users")
    assert table_exists_in_schema?(feature_conn, "branch_feature_rebase", "payments")

    # Reset simulates post-rebase cleanup
    feature_conn.branch_manager.reset

    # Shadowed users should be gone, public users accessible again
    refute table_exists_in_schema?(feature_conn, "branch_feature_rebase", "users")
    refute table_exists_in_schema?(feature_conn, "branch_feature_rebase", "payments")

    result = feature_conn.select_value("SELECT name FROM users LIMIT 1")
    assert_equal "alice", result, "Should fall through to public after reset"
  end

  # Simulates: existing project with a populated public schema adds the adapter.
  # Feature branches should be able to shadow and modify existing tables.
  def test_existing_project_adopts_adapter
    # Simulate pre-adapter state: tables already in public
    main_conn = connect(branch: "main")
    main_conn.create_table(:users) { |t| t.string :name; t.string :email }
    main_conn.create_table(:posts) { |t| t.references :user; t.string :title }
    main_conn.execute("INSERT INTO users (name, email) VALUES ('alice', 'alice@example.com')")

    # Developer starts a feature branch
    feature_conn = reconnect(branch: "feature/profiles")

    # Can read existing data via fallthrough
    result = feature_conn.select_value("SELECT email FROM users LIMIT 1")
    assert_equal "alice@example.com", result

    # Can modify existing tables via shadow
    feature_conn.add_column :users, :bio, :string

    assert column_exists_in_schema?(feature_conn, "branch_feature_profiles", "users", "bio"),
      "Shadow should have the new column"

    count = feature_conn.select_value("SELECT count(*) FROM users")
    assert_equal 1, count, "Shadow should preserve existing data"

    # Public is untouched
    refute column_exists_in_schema?(feature_conn, "public", "users", "bio")
  end

  # Custom primary_branch config: e.g. trunk instead of main.
  def test_custom_primary_branch
    trunk_conn = connect(branch: "trunk", primary_branch: "trunk")
    trunk_conn.create_table(:users) { |t| t.string :name }

    assert table_exists_in_schema?(trunk_conn, "public", "users"),
      "Custom primary branch should write to public"
    refute schema_exists?(trunk_conn, "branch_trunk"),
      "Custom primary branch should not create a branch schema"

    feature_conn = reconnect(branch: "feature/x", primary_branch: "trunk")
    assert schema_exists?(feature_conn, "branch_feature_x")

    result = feature_conn.select_value(
      "SELECT 1 FROM information_schema.tables WHERE table_name = 'users' AND table_schema = 'public'"
    )
    assert_equal 1, result, "Feature branch should see trunk's tables"
  end
end
