require 'simplecov'
require 'logger'
SimpleCov.start

ENV["RACK_ENV"] = "test"

require "minitest/autorun"
require "rack/test"

require_relative "../musicnotes"
require_relative "../database_persistence"

TEST_USERS = { 'test_user' => BCrypt::Password.create('test_user'),
               'test_admin' => BCrypt::Password.create('test_admin') }

class MusicnotesTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def setup
    @storage = DatabasePersistence.new
    @storage.create_test_users(TEST_USERS)
  end

  def teardown
    @storage.delete_test_users(TEST_USERS)
  end

  def user_session
    { 'rack.session' => { username: 'test_user',
                          password: 'test_user' } }
  end

  def admin_session
    { 'rack.session' => { username: 'test_admin',
                          password: 'test_admin' } }
  end

  def session
    last_request.env["rack.session"]
  end

  def check_two_boxes
    post '/', { 'checkbox_group' => ['sunday'] }, user_session
    post '/', { 'checkbox_group' => ['sunday', 'monday'] }, user_session
  end

  def check_all_boxes
    day_list = []
    WEEKDAYS.each do |day|
      day_list << day.downcase
      post '/', { 'checkbox_group' => day_list }, user_session
    end
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
    get '/', {}, user_session
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
    post '/', { 'checkbox_group' => ['sunday'] }, user_session
    assert_equal 302, last_response.status
    assert_includes last_response['Location'], '/'
  end

  def test_no_checkboxes_checked
    get '/', {}, user_session
    assert_equal 200, last_response.status
    refute_includes last_response.body,
                    'onchange="disableThenSubmit()" checked>'
  end

  def test_one_checkbox_checked
    post '/', { 'checkbox_group' => ['sunday'] }, user_session
    get '/', {}, user_session
    assert_includes last_response.body, 'value="sunday" name="checkbox_group[]"
                  id="checkbox_group"
                  onchange="disableThenSubmit()" checked>'
    refute_includes last_response.body, 'value="monday" name="checkbox_group[]"
                  id="checkbox_group"
                  onchange="disableThenSubmit()" checked>'
  end

  def test_two_checkboxes_checked
    check_two_boxes
    get '/', {}, user_session
    assert_includes last_response.body, 'value="sunday" name="checkbox_group[]"
                  id="checkbox_group"
                  onchange="disableThenSubmit()" checked>'
    assert_includes last_response.body, 'value="monday" name="checkbox_group[]"
                  id="checkbox_group"
                  onchange="disableThenSubmit()" checked>'
  end

  def test_final_checkbox_unchecked
    post '/', { 'checkbox_group' => ['sunday'] }, user_session
    post '/', { 'checkbox_group' => nil }, user_session
    get '/', {}, user_session
  end

  def test_reset
    check_two_boxes
    post "/reset", {}, user_session
    assert_equal 302, last_response.status
    assert_includes last_response['Location'], '/'
    get '/', {}, user_session
    refute_includes last_response.body,
                    'onchange="disableThenSubmit()" checked>'
  end

  def test_great_job_flash
    check_all_boxes
    assert_equal "Great job practicing this week!", session[:success]
  end

  def test_reset_success_flash
    post '/', { 'checkbox_group' => ['sunday'] }, user_session
    post '/', { 'checkbox_group' => ['sunday', 'monday'] }, user_session
    post "/reset", {}, user_session
    assert_includes "All days have been unchecked!", session[:success]
  end

  def test_user_login_success
    post '/users/login', { username: 'test_user', password: 'test_user' }
    assert_equal 302, last_response.status
    assert_includes last_response['Location'], '/'
    assert_equal "Welcome Test_user!", session[:success]
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
    post '/users/register', { username: 'test_user' }
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
         { username: 'additional_user', password: 'additional_user',
           confirm_password: 'additional_user' }
    assert_equal 302, last_response.status
    assert_equal "User Additional_user created!", session[:success]

    get '/', { username: 'additional_user' }
    assert_includes last_response['Location'], '/'
    @storage.delete_user('additional_user')
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

  def test_admin_choose_student_practice
    post '/users/select', { student: "test" }, admin_session

    assert_equal 302, last_response.status
    assert_includes last_response['Location'], '/users/practice/test'
  end

  def test_admin_display_student_practice_success
    get '/users/practice/test_user', {}, admin_session

    assert_equal 200, last_response.status
    assert_includes last_response.body, "<title>My Music Notes: Test_user " \
                                        "Practice Log</title>"
    assert_includes last_response.body, "<h1>Test_user's Practice Log</h1>"
    assert_includes last_response.body, " disabled selected>Test_user</option>"
  end

  def test_admin_display_student_practice_failure
    get '/users/practice/test', {}

    assert_equal 302, last_response.status
    assert_equal "You do not have permission to view this page.",
                 session[:error]
  end
end
