require 'simplecov'
SimpleCov.start

ENV["RACK_ENV"] = "test"

require "minitest/autorun"
require "rack/test"

require_relative "../musicnotes"

class MusicnotesTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def setup
    user_name = 'test'
    password = BCrypt::Password.create('test')
    query = "DELETE FROM users WHERE name = '#{user_name}';" \
            "INSERT INTO users (name, password) VALUES " \
            "('#{user_name}', '#{password}');"
    CONN.exec(query)
    add_user_checkboxes(user_name)
  end

  def teardown
    user_name = 'test'
    query = "DELETE FROM users WHERE name = '#{user_name}';"
    CONN.exec(query)
  end

  def test_session
    { 'rack.session' => { username: 'test',
                          password: 'test' } }
  end

  def session
    last_request.env["rack.session"]
  end

  def params_all_days_checked
    DAYS.map(&:downcase).to_h { |day| ["#{day}_check".to_sym, "checked"] }
  end

  def test_index_no_login
    get '/'
    assert_equal 302, last_response.status

    get '/users/login'
    assert_equal 200, last_response.status
    assert_includes last_response.body, "Log In"
    assert_includes last_response.body, "a tool to track"
  end

  def test_index_yes_login
    get '/', {}, test_session
    assert_equal 200, last_response.status
  end

  def test_check_checkbox_no_login
    post '/'
    assert_equal 302, last_response.status
    assert_includes last_response['Location'], '/users/login'
  end

  def test_check_checkbox_yes_login
    post '/', {}, test_session
    assert_equal 302, last_response.status
    assert_includes last_response['Location'], '/'
  end

  def test_no_checkboxes_checked
    get '/', {}, test_session
    assert_equal 200, last_response.status
    refute_includes last_response.body,
                    'onchange="disableThenSubmit()" checked>'
  end

  def test_one_checkbox_checked
    post '/', { sunday_check: "checked" }, test_session
    get '/', {}, test_session
    assert_includes last_response.body, 'id="sunday_check"
                  onchange="disableThenSubmit()" checked>'
    refute_includes last_response.body, 'id="monday_check"
                  onchange="disableThenSubmit()" checked>'
  end

  def test_two_checkboxes_checked
    post '/', { sunday_check: "checked", monday_check: "checked" }, test_session
    get '/', {}, test_session
    assert_includes last_response.body, 'id="sunday_check"
                  onchange="disableThenSubmit()" checked>'
    assert_includes last_response.body, 'id="monday_check"
                  onchange="disableThenSubmit()" checked>'
    refute_includes last_response.body, 'id="tuesday_check"
                  onchange="disableThenSubmit()" checked>'
  end

  def test_all_checkboxes_checked
    post '/', params_all_days_checked, test_session
    get '/', {}, test_session
    assert_includes last_response.body, 'id="sunday_check"
                  onchange="disableThenSubmit()" checked>'
    assert_includes last_response.body, 'id="monday_check"
                  onchange="disableThenSubmit()" checked>'
    assert_includes last_response.body, 'id="tuesday_check"
                  onchange="disableThenSubmit()" checked>'
    assert_includes last_response.body, 'id="wednesday_check"
                  onchange="disableThenSubmit()" checked>'
    assert_includes last_response.body, 'id="thursday_check"
                  onchange="disableThenSubmit()" checked>'
    assert_includes last_response.body, 'id="friday_check"
                  onchange="disableThenSubmit()" checked>'
    assert_includes last_response.body, 'id="saturday_check"
                  onchange="disableThenSubmit()" checked>'
  end

  def test_great_job_flash
    post '/', params_all_days_checked, test_session
    assert_equal "Great job practicing this week!", session[:success]
  end

  def test_reset
    post "/reset", params_all_days_checked, test_session
    assert_equal 302, last_response.status
    assert_includes last_response['Location'], '/'
    get '/', {}, test_session
    assert_includes last_response.body, 'id="sunday_check"
                  onchange="disableThenSubmit()">'
    assert_includes last_response.body, 'id="monday_check"
                  onchange="disableThenSubmit()">'
    assert_includes last_response.body, 'id="tuesday_check"
                  onchange="disableThenSubmit()">'
    assert_includes last_response.body, 'id="wednesday_check"
                  onchange="disableThenSubmit()">'
    assert_includes last_response.body, 'id="thursday_check"
                  onchange="disableThenSubmit()">'
    assert_includes last_response.body, 'id="friday_check"
                  onchange="disableThenSubmit()">'
    assert_includes last_response.body, 'id="saturday_check"
                  onchange="disableThenSubmit()">'
  end

  def test_reset_success_flash
    post "/reset", params_all_days_checked, test_session
    assert_includes "All days have been unchecked!", session[:success]
  end
end
