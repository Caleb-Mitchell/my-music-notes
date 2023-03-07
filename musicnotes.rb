require "bcrypt"
require "sinatra"
require "tilt/erubis"

require_relative "database_persistence"

SECRET = SecureRandom.hex(32)
WEEKDAYS = %w(Sunday Monday Tuesday Wednesday Thursday Friday Saturday)

configure do
  enable :sessions
  set :session_secret, SECRET
  set :erb, escape_html: true
end

configure(:development) do
  require "sinatra/reloader" if development?
  also_reload "database_persistence.rb"
end

helpers do
  def day_checked?(checkboxes, day)
    checkboxes.find { |hash| hash[:day] == day.downcase }[:checked]
  end

  def admin_session?
    session[:username] == "admin" || session[:username] == "test_admin"
  end
end

def user_logged_in?
  session.key?(:username)
end

def require_logged_in_user
  return if user_logged_in?

  session[:error] = "You must be logged in to do that."
  redirect '/users/login'
end

def require_admin_session
  return if admin_session?

  session[:error] = "You do not have permission to view this page."
  redirect '/users/login'
end

def valid_credentials?(username, password)
  credentials = @storage.find_all_user_credentials

  credentials.each do |cred|
    if cred["name"] == username
      bcrypt_password = BCrypt::Password.new(cred["password"])
      return bcrypt_password == password
    end
  end
  false
end

def practice_every_day?(name)
  checkboxes = @storage.load_user_checkboxes(name)
  (checkboxes.count { |tuple| tuple[:checked] == true }) == WEEKDAYS.size
end

def username_taken?(name)
  names = @storage.find_all_user_names
  names.to_a.find { |hash| hash["name"] == name }
end

before do
  @storage = DatabasePersistence.new(logger)
end

# Main practice log page
get '/' do
  redirect '/users/login' unless user_logged_in?
  require_logged_in_user

  @title = "Practice Log"
  session[:checkboxes] = @storage.load_user_checkboxes(session[:username])
  @day_total = session[:checkboxes].count { |day| day[:checked] == true }

  if admin_session?
    @users = @storage.find_all_user_names.map { |user| user["name"] }
  end

  erb :practice
end

# Update page on checkbox toggle
post '/' do
  require_logged_in_user

  name = session[:username]
  student_id = @storage.find_student_id(name)
  @storage.update_checkboxes(params, name, student_id)

  if practice_every_day?(name)
    session[:success] = "Great job practicing this week!"
  end

  redirect '/'
end

# Ask user to log in or register
get '/users/login' do
  @title = "Log In"

  erb :login
end

# Allow user to log in
post '/users/login' do
  if valid_credentials?(params[:username], params[:password])
    username = params[:username]

    session[:username] = username
    session[:checkboxes] = @storage.load_user_checkboxes(username)
    session[:success] = "Welcome #{username.capitalize}!"

    redirect '/'
  else
    session[:error] = "Invalid credentials."
    status 422

    erb :login
  end
end

# Allow user to log out
post '/users/logout' do
  session.delete(:username)
  session[:success] = "You have been logged out."

  redirect '/users/login'
end

# Reset all checkboxes to unchecked
post '/reset' do
  require_logged_in_user

  @storage.reset_checkboxes(session[:username])
  session[:success] = "All days have been unchecked!"

  redirect '/'
end

# Request practice log of user from admin login
post '/users/select' do
  student = params[:student]

  redirect "/users/practice/#{student}"
end

# Display practice log of user from admin login
get '/users/practice/:student' do
  require_admin_session

  @student = params[:student]
  @title = "#{@student.capitalize} Practice Log"
  @users = @storage.find_all_user_names.map { |user| user["name"] }
  session[:checkboxes] = @storage.load_user_checkboxes(@student)
  @day_total = session[:checkboxes].count { |day| day["checked"] == "t" }

  erb :admin_practice
end

# Ask user to register
get '/users/register' do
  @title = "Register"

  erb :register
end

# Allow user to register
# rubocop:disable Metrics/BlockLength
post '/users/register' do
  username = params[:username]

  if username.nil? || username.squeeze == " "
    session[:error] = "Please provide a username."
    status 422
    erb :register
  elsif username_taken?(username)
    session[:error] = "Sorry, that username is already taken."
    status 422
    erb :register
  elsif params[:password].nil?
    session[:error] = "Please provide a password."
    status 422
    erb :register
  elsif params[:password] != params[:confirm_password]
    session[:error] = "Passwords do not match."
    status 422
    erb :register
  else
    @storage.create_user(username, params[:password])
    session[:success] = "User #{username.capitalize} created!"
    redirect '/'
  end
end
# rubocop:enable Metrics/BlockLength

# Show listening recomendations
get '/listen' do
  @title = "Listening Recs"

  erb :listen
end
