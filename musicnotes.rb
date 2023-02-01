require "bcrypt"
require "pg"
require "sinatra"
require "sinatra/reloader" if development?
require "tilt/erubis"

DAYS = %w(Sunday Monday Tuesday Wednesday Thursday Friday Saturday)
DAYS_IN_WEEK = DAYS.size

SECRET = SecureRandom.hex(32)

CONN = PG.connect(dbname: 'musicnotes') if development?
CONN = PG.connect(ENV.fetch('RAILWAY_DATABASE_URL', nil)) if production?

configure do
  enable :sessions
  set :session_secret, SECRET
  set :erb, escape_html: true
end

helpers do
  def day_checked?(checkboxes, day)
    checkboxes.find { |hash| hash["day"] == day.downcase }["checked"] == "t"
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

def load_user_credentials
  credentials = []
  CONN.transaction do |trans_conn|
    trans_conn.exec("SELECT * FROM users") do |result|
      result.each do |row|
        credentials << row
      end
    end
  end
  credentials
end

def find_student_id(username)
  student_id = nil
  CONN.transaction do |trans_conn|
    trans_conn.exec("SELECT id FROM users WHERE name = '#{username}'") do |result|
      result.each { |row| student_id = row["id"] }
    end
  end
  student_id
end

def load_user_checkboxes(username)
  student_id = find_student_id(username)

  checkboxes = []
  query = "SELECT day, checked FROM checkboxes WHERE user_id = #{student_id}"
  CONN.transaction do |trans_conn|
    trans_conn.exec(query) do |result|
      result.each { |row| checkboxes << row }
    end
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
  CONN.transaction do |trans_conn|
    query = "SELECT COUNT(id) FROM checkboxes WHERE checked = true
             AND user_id = #{student_id}"
    trans_conn.exec(query) do |result|
      result.each { |row| count = row["count"] }
    end
  end
  count.to_i == DAYS_IN_WEEK
end

def username_taken?(name)
  query = "SELECT COUNT(id) FROM users WHERE name = '#{name.downcase}'"
  CONN.transaction do |trans_conn|
    trans_conn.exec(query) do |result|
      return result.values.flatten[0] == "1"
    end
  end
end

def log_in_user(username)
  session[:username] = username
  session[:success] = "User #{username.capitalize} created!"
end

def add_user_checkboxes(username)
  user_id = find_student_id(username)
  days = DAYS
  CONN.transaction do |trans_conn|
    days.each do |day|
      trans_conn.exec("INSERT INTO checkboxes (day, user_id)
                   VALUES ('#{day.downcase}', #{user_id})")
    end
  end
end

def create_new_user(username, password)
  username = username.downcase
  hashed_password = BCrypt::Password.create(password)
  CONN.transaction do |trans_conn|
    trans_conn.exec("INSERT INTO users (name, password)
               VALUES ('#{username}', '#{hashed_password}')")
  end
  add_user_checkboxes(username)
  log_in_user(username)
end

# Main practice log page
get '/' do
  redirect '/users/login' unless user_logged_in?
  require_logged_in_user

  @title = "Practice Log"
  @days = DAYS

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
  @days.each do |day|
    name = "#{day.downcase}_check"
    checked = (params[name] == 'checked')

    CONN.transaction do |trans_conn|
      trans_conn.exec("UPDATE checkboxes SET checked = '#{checked}'
                   WHERE day = '#{day.downcase}'
                   AND user_id = #{student_id.to_i}")
    end

    if practice_every_day?(student_id)
      session[:success] = "Great job practicing this week!"
    end
  end

  redirect '/'
end

# Allow user to log in
get '/users/login' do
  @title = "Log In"

  erb :login
end

post '/users/login' do
  username = params[:username].downcase

  if valid_credentials?(username, params[:password])
    session[:username] = username
    session[:success] = "Welcome #{username.capitalize}!"

    # checkboxes is an array, with each checkbox represented by a hash
    # with keys "day" and "checked"
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

  @days.each do |day|
    CONN.transaction do |trans_conn|
      trans_conn.exec("UPDATE checkboxes SET checked = false
                   WHERE day = '#{day.downcase}'
                   AND user_id = #{student_id.to_i}")
    end
  end

  redirect '/'
end

# Allow user to register
get '/users/register' do
  @title = "Register"

  erb :register
end

post '/users/register' do
  username = params[:username]

  if username_taken?(username)
    session[:error] = "Sorry, that username is already taken."
    status 422
    erb :register
  elsif username.empty?
    session[:error] = "Please provide a username."
    status 422
    erb :register
  elsif params[:password].empty?
    session[:error] = "Please provide a password."
    status 422
    erb :register
  else
    create_new_user(username, params[:password])
    redirect '/'
  end
end

# Show listening recomendations
get '/listen' do
  @title = "Listening Recs"

  erb :listen
end
