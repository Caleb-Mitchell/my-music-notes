# TODO: make other links work
# TODO: Add listening page
# TODO: put link to database in environment variable
# TODO: escape all input
# TODO: REdo table, make more semantic throughout, flexbox?
# TODO: add validation like in todos
# TODO: add tests?
# TODO: Update details on resume
# TODO: Update README and description for Github
# TODO: Change silly navbar collapse stuff

# resume stuff
# TODO: add more specific time frames for CiP and CS50 to resume
# TODO: add cip hangman project to resume


require "bcrypt"
require "pg"
require "sinatra"
require "sinatra/reloader" if development?
require "tilt/erubis"

DAYS_IN_WEEK = 7
DAYS = %w(Sunday Monday Tuesday Wednesday Thursday Friday Saturday)

SECRET = SecureRandom.hex(32)

CONN = PG.connect(ENV['RAILWAY_DATABASE_URL'])
# CONN = PG.connect( dbname: 'musicnotes' )

configure do
  enable :sessions
  set :session_secret, SECRET
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
  CONN.exec( "SELECT * FROM users" ) do |result|
    result.each do |row|
      credentials << row
    end
  end
  credentials
end

def find_student_id(username)
  student_id = nil
  CONN.exec ( "SELECT id FROM users WHERE name = '#{username}'" ) do |result|
    result.each { |row| student_id = row["id"] }
  end
  student_id
end

def load_user_checkboxes(username)
  student_id = find_student_id(username)

  checkboxes = []
  CONN.exec ( "SELECT day, checked FROM checkboxes WHERE user_id = #{student_id}" ) do |result|
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

def full_week?
  count = nil
  CONN.exec("SELECT COUNT(id) FROM checkboxes WHERE checked = true") do |result|
    result.each { |row| count = row["count"] }
  end
  count.to_i == DAYS_IN_WEEK
end

# Main practice log page
get '/' do
  # require_signed_in_user

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
  # TODO: clean this up
  @days.each do |day|
    name = "#{day.downcase}_check"
    if params[name] == 'checked'
      CONN.exec ( "UPDATE checkboxes SET checked = true WHERE day = '#{day.downcase}'
                 AND user_id = #{student_id.to_i}")
    else
      CONN.exec ( "UPDATE checkboxes SET checked = false WHERE day = '#{day.downcase}'
                 AND user_id = #{student_id.to_i}")
    end
  end

  # flash message if checkbox list is full of 1s
  session[:success] = "Great job practicing this week!" if full_week?

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
    session[:success] = "Welcome!"

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
  # TODO: clean this up
  @days.each do |day|
    name = "#{day.downcase}_check"
      CONN.exec ( "UPDATE checkboxes SET checked = false WHERE day = '#{day.downcase}'
                 AND user_id = #{student_id.to_i}")
  end

  # flash message if checkbox list is full of 1s
  session[:success] = "Great job practicing this week!" if full_week?

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
  CONN.exec ( "INSERT INTO users (name, password) VALUES ('#{username}', '#{password}')")

  # get user_id from users for new user
  user_id = find_student_id(username)

  # add rows to checkboxes table
  days = DAYS
  days.each do |day|
    CONN.exec ( "INSERT INTO checkboxes (day, user_id) VALUES ('#{day.downcase}', #{user_id})")
  end

  # sign in to new user
  session[:username] = username
  session[:success] = "User #{username} created!"

  redirect '/'
end
