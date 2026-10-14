require "test_helper"

class Procore::UtilTest < Minitest::Test
  def setup
    @output = StringIO.new
    Procore.configuration.logger = Logger.new(@output)
  end

  def teardown
    Procore.configuration.logger = nil
  end

  def test_log_info
    Procore::Util.log_info("Hello")
    assert_match /Hello/, @output.string
  end

  def test_log_info_redacts_bearer_token
    Procore::Util.log_info(
      "Request",
      headers: { "Authorization" => "Bearer abc.DEF-123_xyz=" },
    )

    refute_includes @output.string, "abc.DEF-123_xyz"
    assert_includes @output.string, "Bearer ###"
  end

  def test_log_error_redacts_bearer_token
    Procore::Util.log_error(
      "Request failed",
      headers: { "Authorization" => "Bearer abc.DEF-123_xyz=" },
    )

    refute_includes @output.string, "abc.DEF-123_xyz"
    assert_includes @output.string, "Bearer ###"
  end

  def test_log_info_redacts_bearer_token_in_message
    Procore::Util.log_info("Sent Authorization: bearer secret-token")

    refute_includes @output.string, "secret-token"
    assert_includes @output.string, "bearer ###"
  end

  def test_log_info_keeps_text_without_bearer_token
    Procore::Util.log_info("Request", path: "/rest/v1.0/projects?per_page=5")

    assert_includes @output.string, "/rest/v1.0/projects?per_page=5"
  end
end
