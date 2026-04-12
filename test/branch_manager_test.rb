require "test_helper"

class BranchManagerTest < Minitest::Test
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
end
