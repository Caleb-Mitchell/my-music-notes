# TODO: REdo table, make more semantic throughout, flexbox?
# TODO: add validation like in todos
# TODO: add tests?
# TODO: Update details on resume
# TODO: Update README and description for Github
# TODO: set up apology page

# resume stuff
# TODO: add more specific time frames for CiP and CS50 to resume
# TODO: add cip hangman project to resume

require "bcrypt"
require "pg"
require "sinatra"
require "sinatra/reloader" if development?
require "tilt/erubis"

DAYS = %w(Sunday Monday Tuesday Wednesday Thursday Friday Saturday)
DAYS_IN_WEEK = DAYS.size

SECRET = SecureRandom.hex(32)

CONN = PG.connect(dbname: 'musicnotes') if development?
CONN = PG.connect(ENV.fetch['RAILWAY_DATABASE_URL']) if production?

configure do
  enable :sessions
  set :session_secret, SECRET
  set :erb, escape_html: true
end

def user_signed_in?
  session.key?(:username)
end

def require_signed_in_user
  return if user_signed_in?

  session[:error] = "You must be signed in to do that"
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

def full_week?(student_id)
  count = nil
  query = "SELECT COUNT(id) FROM checkboxes WHERE checked = true
           AND user_id = #{student_id}"
  CONN.exec(query) do |result|
    result.each { |row| count = row["count"] }
  end
  count.to_i == DAYS_IN_WEEK
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

  # update check values in checkboxes database
  @days.each do |day|
    name = "#{day.downcase}_check"
    if params[name] == 'checked'
      CONN.exec("UPDATE checkboxes SET checked = true
                 WHERE day = '#{day.downcase}'
                 AND user_id = #{student_id.to_i}")
    else
      CONN.exec("UPDATE checkboxes SET checked = false
                 WHERE day = '#{day.downcase}'
                 AND user_id = #{student_id.to_i}")
    end
  end

  if full_week?(student_id)
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
  username = params[:username]

  if valid_credentials?(username, params[:password])
    session[:username] = username
    session[:success] = "Welcome #{username}!"

    # checkboxes is an array, with each checkbox represented by a hash
    # with keys "day" and "checked"
    load_user_checkboxes(username)

    redirect '/'
  else
    session[:error] = "Invalid credentials."
    status 422
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
  @days.each do |day|
    CONN.exec("UPDATE checkboxes SET checked = false
               WHERE day = '#{day.downcase}'
               AND user_id = #{student_id.to_i}")
  end

  redirect '/'
end

# Allow user to register
get '/users/register' do
  erb :register
end

post '/users/register' do
  username = params[:username]
  password = BCrypt::Password.create(params[:password])

  # add row to users table
  CONN.exec("INSERT INTO users (name, password)
             VALUES ('#{username}', '#{password}')")

  # get user_id from users for new user
  user_id = find_student_id(username)

  # add rows to checkboxes table
  days = DAYS
  days.each do |day|
    CONN.exec("INSERT INTO checkboxes (day, user_id)
               VALUES ('#{day.downcase}', #{user_id})")
  end

  # sign in to new user
  session[:username] = username
  session[:success] = "User #{username} created!"

  redirect '/'
end

# Show listening recomendations
get '/listen' do
  erb :listen
end
