require "bcrypt"
require "sinatra"
require "tilt/erubis"

require_relative "database_persistence"

SECRET = SecureRandom.hex(32)

DAYS = %w(Sunday Monday Tuesday Wednesday Thursday Friday Saturday)
DAYS_COUNT = DAYS.size

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
    checkboxes.find { |hash| hash["day"] == day.downcase }["checked"] == "t"
  end

  def admin_session?
    session[:username] == "admin"
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

def load_user_credentials
  credentials = []
  CONN.exec("SELECT * FROM users") do |result|
    result.each do |row|
      credentials << row
    end
  end
  credentials
end

def find_student_id(username)
  student_id = nil
  CONN.exec("SELECT id FROM users WHERE name = '#{username}'") do |result|
    result.each { |row| student_id = row["id"] }
  end
  student_id
end

def load_user_checkboxes(username)
  student_id = find_student_id(username)

  checkboxes = []
  query = "SELECT day, checked FROM checkboxes WHERE user_id = #{student_id}"
  CONN.exec(query) do |result|
    result.each { |row| checkboxes << row }
  end
  session[:checkboxes] = checkboxes
end

def valid_credentials?(username, password)
  credentials = load_user_credentials

  credentials.each do |cred|
    if cred["name"] == username
      bcrypt_password = BCrypt::Password.new(cred["password"])
      return bcrypt_password == password
    end
  end
  false
end

def practice_every_day?(student_id)
  count = nil
  query = "SELECT COUNT(id) FROM checkboxes WHERE checked = true
           AND user_id = #{student_id}"
  CONN.exec(query) do |result|
    result.each { |row| count = row["count"] }
  end
  count.to_i == DAYS_COUNT
end

def username_taken?(name)
  query = "SELECT COUNT(id) FROM users WHERE name = '#{name.downcase}'"
  CONN.exec(query) do |result|
    return result.values.flatten[0] == "1"
  end
end

def log_in_user(username)
  session[:username] = username
  session[:success] = "User #{username.capitalize} created!"
end

def add_user_checkboxes(username)
  user_id = find_student_id(username)
  days = DAYS

  query = ''
  days.each do |day|
    query << "INSERT INTO checkboxes (day, user_id)
                 VALUES ('#{day.downcase}', #{user_id});"
  end
  CONN.exec(query)
end

def create_new_user(username, password)
  username = username.downcase
  hashed_password = BCrypt::Password.create(password)
  CONN.exec("INSERT INTO users (name, password)
             VALUES ('#{username}', '#{hashed_password}')")
  add_user_checkboxes(username)
  log_in_user(username)
end

# Main practice log page
get '/' do
  redirect '/users/login' unless user_logged_in?
  require_logged_in_user

  @title = "Practice Log"
  @days = DAYS

  if admin_session?
    @users = load_user_credentials.map { |user| user["name"] }
  end

  load_user_checkboxes(session[:username])
  @day_total = session[:checkboxes].count { |day| day["checked"] == "t" }

  erb :practice
end

# Update page on checkbox toggle
post '/' do
  require_logged_in_user

  @days = DAYS
  student_id = find_student_id(session[:username])

  # update check values in checkboxes database
  query = ''
  @days.each do |day|
    name = "#{day.downcase}_check"
    checked = (params[name] == 'checked')
    query << "UPDATE checkboxes SET checked = '#{checked}'
                 WHERE day = '#{day.downcase}'
                 AND user_id = #{student_id.to_i};"
  end
  CONN.exec(query)

  if practice_every_day?(student_id)
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
    session[:success] = "Welcome #{username.capitalize}!"

    # checkboxes is an array, with each checkbox represented by a hash
    # example: [{"day"=>"sunday", "checked"=>"t"},
    #           {"day"=>"monday", "checked"=>"t"},
    #           {"day"=>"tuesday", "checked"=>"f"},
    #           {"day"=>"wednesday", "checked"=>"f"} ... ]
    load_user_checkboxes(username)

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

  @days = DAYS
  student_id = find_student_id(session[:username])

  query = ''
  @days.each do |day|
    query << "UPDATE checkboxes SET checked = false
                 WHERE day = '#{day.downcase}'
                 AND user_id = #{student_id.to_i};"
  end
  CONN.exec(query)

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
  @users = load_user_credentials.map { |user| user["name"] }
  @days = DAYS

  load_user_checkboxes(@student)
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
    create_new_user(username, params[:password])
    redirect '/'
  end
end
# rubocop:enable Metrics/BlockLength

# Show listening recomendations
get '/listen' do
  @title = "Listening Recs"

  erb :listen
end
