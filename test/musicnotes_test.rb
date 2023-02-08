ENV["RACK_ENV"] = "test"

require "minitest/autorun"
require "rack/test"

require_relative "../musicnotes"

class MusicnotesTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  # def admin_session
  #   { "rack.session" => { username: "admin" } }
  # end

  def session
    last_request.env["rack.session"]
  end

  def test_index
    get "/"
    assert_equal 302, last_response.status

    get "/users/login"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "Log In"
  end

  def test_reset
    post "/reset", {}, admin_session

    assert_includes "All days have been unchecked!", session[:success]
  end
end
