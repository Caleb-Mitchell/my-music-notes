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
    users = { 'test' => BCrypt::Password.create('test'),
              'admin' => BCrypt::Password.create('admin') }

    query = ''
    users.each do |name, pass|
      query << "DELETE FROM users WHERE name = '#{name}';"
      query << "INSERT INTO users (name, password) VALUES " \
               "('#{name}', '#{pass}');"
    end
    CONN.exec(query)
    users.each_key { |user| add_user_checkboxes(user) }
  end

  def teardown
    users = ['test', 'test_user_new', 'admin']
    query = ''
    users.each do |user|
      query << "DELETE FROM users WHERE name = '#{user}';"
    end
    CONN.exec(query)
  end

  def test_session
    { 'rack.session' => { username: 'test',
                          password: 'test' } }
  end

  def admin_session
    { 'rack.session' => { username: 'admin',
                          password: 'admin' } }
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

  def test_index_login_success
    get '/', {}, test_session
    assert_equal 200, last_response.status
  end

  def test_index_login_admin_success
    get '/', {}, admin_session
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

  def test_user_login_success
    post '/users/login', { username: 'test', password: 'test' }
    assert_equal 302, last_response.status
    assert_includes last_response['Location'], '/'
    assert_equal "Welcome Test!", session[:success]
  end

  def test_user_login_failure
    post '/users/login'
    assert_equal 422, last_response.status
    assert_includes last_response.body, 'Invalid credentials'
  end

  def test_user_logout
    post '/users/logout'
    assert_nil session[:username]
    assert_equal "You have been logged out.", session[:success]
  end

  def test_register_new_user_failure_no_name
    post '/users/register'
    assert_includes last_response.body, 'Please provide a username.'
    assert_equal 422, last_response.status
  end

  def test_register_new_user_failure_name_empty_string
    post '/users/register'
    assert_includes last_response.body, 'Please provide a username.'
    assert_equal 422, last_response.status
  end

  def test_register_new_user_failure_name_taken
    post '/users/register', { username: 'test' }
    assert_includes last_response.body, 'Sorry, that username is already taken.'
    assert_equal 422, last_response.status
  end

  def test_register_new_user_failure_no_password
    post '/users/register', { username: 'test_uniq' }
    assert_includes last_response.body, 'Please provide a password.'
    assert_equal 422, last_response.status
  end

  def test_register_new_user_failure_passwords_do_not_match
    post '/users/register',
         { username: 'test_uniq', password: 'test',
           confirm_password: 'not_test' }
    assert_includes last_response.body, 'Passwords do not match.'
    assert_equal 422, last_response.status
  end

  def test_register_new_user_success
    post '/users/register',
         { username: 'test_user_new', password: 'test_pass_new',
           confirm_password: 'test_pass_new' }

    assert_equal 302, last_response.status
    assert_equal "User Test_user_new created!", session[:success]
    assert_includes last_response['Location'], '/'
  end

  def test_show_register_page
    get '/users/register'
    assert_equal 200, last_response.status
    assert_includes last_response.body,
                    "<form action='/users/register' method='post' class='form'>"
  end

  def test_show_listen_rec_page
    get '/listen'
    assert_equal 200, last_response.status
    assert_includes last_response.body, "<h1>LISTENING RECS</h1>"
  end
end
