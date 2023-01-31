# TODO: provide helpful status codes on errors or redirection
# TODO: add tests?
# TODO: Update details on resume
# TODO: Update README and description for Github
# TODO: set up apology page?
# TODO: title instance var for every page GET?

# resume stuff
# TODO: add more specific time frames for CiP and CS50 to resume
# TODO: add cip hangman project to resume

# TODO: Add gem versions to GEMFILE

require "bcrypt"
require "pg"
require "sinatra"
require "sinatra/reloader" if development?
require "thread"
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

def user_signed_in?
  session.key?(:username)
end

def require_signed_in_user
  return if user_signed_in?

  session[:error] = "You must be signed in to do that."
  redirect '/users/signin'
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
  count.to_i == DAYS_IN_WEEK
end

def username_taken?(name)
  query = "SELECT COUNT(id) FROM users WHERE name = '#{name.downcase}'"
  CONN.exec(query) do |result|
    return result.values.flatten[0] == "1"
  end
end

def sign_in_user(username)
  session[:username] = username
  session[:success] = "User #{username.capitalize} created!"
end

def add_user_checkboxes(username)
  user_id = find_student_id(username)
  days = DAYS
  days.each do |day|
    CONN.exec("INSERT INTO checkboxes (day, user_id)
               VALUES ('#{day.downcase}', #{user_id})")
  end
end

def create_new_user(username, password)
  username = username.downcase
  hashed_password = BCrypt::Password.create(password)
  CONN.exec("INSERT INTO users (name, password)
             VALUES ('#{username}', '#{hashed_password}')")
  add_user_checkboxes(username)
  sign_in_user(username)
end

# Main practice log page
get '/' do
  redirect '/users/signin' unless user_signed_in?
  require_signed_in_user

  @title = "Practice Log"
  @days = DAYS

  load_user_checkboxes(session[:username])
  @day_total = session[:checkboxes].count { |day| day["checked"] == "t" }

  erb :practice
end

# Update page on checkbox toggle
post '/' do
  require_signed_in_user

  @days = DAYS
  student_id = find_student_id(session[:username])

  # only made request if database has data for all 7 days, for that user
  # if not, store a flash message saying to slow down, and redisplay the page
  # not sure if issue is upon account creation, or on update, will test on update first

  # update check values in checkboxes database

  @db_mutex = Mutex.new
  @days.each do |day|
    name = "#{day.downcase}_check"
    checked = (params[name] == 'checked')

    @db_mutex.synchronize do
      CONN.exec("UPDATE checkboxes SET checked = '#{checked}'
                 WHERE day = '#{day.downcase}'
                 AND user_id = #{student_id.to_i}")
    end
  end

  if practice_every_day?(student_id)
    session[:success] = "Great job practicing this week!"
  end

  redirect '/'
end

# Allow user to sign in
get '/users/signin' do
  @title = "Sign In"
  erb :signin
end

post '/users/signin' do
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
    # status 422
    erb :signin
  end
end

# Allow user to sign out
post '/users/signout' do
  session.delete(:username)
  session[:success] = "You have been signed out."
  redirect '/users/signin'
end

# Reset all checkboxes to unchecked
post '/reset' do
  require_signed_in_user

  @days = DAYS
  student_id = find_student_id(session[:username])

  # update check values in checkboxes database

  @db_mutex = Mutex.new

  @days.each do |day|
    @db_mutex.synchronize do
      CONN.exec("UPDATE checkboxes SET checked = false
                 WHERE day = '#{day.downcase}'
                 AND user_id = #{student_id.to_i}")
    end
  end

  redirect '/'
end

# Allow user to register
get '/users/register' do
  erb :register
end

post '/users/register' do
  username = params[:username]

  if username_taken?(username)
    session[:error] = "Sorry, that username is already taken."
    # status 422
    erb :register
  elsif username.empty?
    session[:error] = "Please provide a username."
    # status 422
    erb :register
  elsif params[:password].empty?
    session[:error] = "Please provide a password."
    # status 422
    erb :register
  else
    create_new_user(username, params[:password])
    redirect '/'
  end
end

# Show listening recomendations
get '/listen' do
  erb :listen
end
