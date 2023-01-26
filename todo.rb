require "sinatra"
require "sinatra/reloader" if development?
require "sinatra/content_for"
require "tilt/erubis"

configure do
  enable :sessions
  set :session_secret, 'secret'
end

before do
  session[:lists] ||= []
end

# rubocop:disable Metrics/BlockLength
helpers do
  def list_complete?(list)
    todos_remaining_count(list).zero? && !todos_count(list).zero?
  end

  def list_class(list)
    "complete" if list_complete?(list)
  end

  def todos_remaining_count(list)
    list[:todos].count { |todo| todo[:completed] == false }
  end

  def todos_count(list)
    list[:todos].size
  end

  def sort_lists(lists, &block)
    complete_lists, incomplete_lists = lists.partition do |list|
      list_complete?(list)
    end

    incomplete_lists.each(&block)
    complete_lists.each(&block)
  end

  def sort_todos(todos)
    complete_todos, incomplete_todos = todos.partition do |todo|
      todo[:completed]
    end

    incomplete_todos.each do |todo|
      yield todo, todos.index(todo)
    end
    complete_todos.each do |todo|
      yield todo, todos.index(todo)
    end
  end
end
# rubocop:enable Metrics/BlockLength

# Return an error message if the name is invalid. Return nil if name is valid.
def error_for_list_name(name)
  if !(1..100).cover? name.size
    "List name must be between 1 and 100 characters."
  elsif session[:lists].any? { |list| list[:name] == name }
    "List name must be unique."
  end
end

# Return an error message if the name is invalid. Return nil if name is valid.
def error_for_todo(name)
  "Todo must be between 1 and 100 characters." unless (1..100).cover? name.size
end

# Validate that requested list id exists and is valid
def load_list(id)
  list = session[:lists].find { |session_list| session_list[:id] == id }
  return list if list

  session[:error] = "The specified list was not found."
  redirect "/lists"
end

# Generate the next available id number for a given collection
def next_element_id(elements)
  max = elements.map { |element| element[:id] }.max || 0
  max + 1
end

get "/" do
  redirect "/lists"
end

# View list of lists
get "/lists" do
  @lists = session[:lists]
  erb :lists, layout: :layout
end

# Render the new list form
get "/lists/new" do
  erb :new_list, layout: :layout
end

# Create a new list
post "/lists" do
  list_name = params[:list_name].strip

  error = error_for_list_name(list_name)
  if error
    session[:error] = error
    erb :new_list, layout: :layout
  else
    id_num = next_element_id(session[:lists])
    session[:lists] << { id: id_num, name: list_name, todos: [] }
    session[:success] = "The list has been created."
    redirect "/lists"
  end
end

# View a single todo list
get "/lists/:id" do
  id = params[:id].to_i
  @list = load_list(id)

  @list_name = @list[:name]
  @list_id = @list[:id]
  @todos = @list[:todos]
  erb :list, layout: :layout
end

# Edit an existing todo list
get "/lists/:id/edit" do
  @id = params[:id].to_i
  @list = load_list(@id)
  erb :edit_list, layout: :layout
end

# Update an existing todo list
post "/lists/:id" do
  list_name = params[:list_name].strip
  @id = params[:id].to_i
  @list = load_list(@id)

  error = error_for_list_name(list_name)
  if error
    session[:error] = error
    erb :edit_list, layout: :layout
  else
    @list[:name] = list_name
    session[:success] = "The list has been updated."
    redirect "/lists/#{@id}"
  end
end

# Delete a todo list
post "/lists/:id/delete" do
  id = params[:id].to_i
  list_name = load_list(id)[:name]

  session[:lists].reject! { |list| list[:id] == id }
  session[:success] = "List \"#{list_name}\" has been deleted."

  if env["HTTP_X_REQUESTED_WITH"] == "XMLHttpRequest"
    "/lists"
  else
    redirect "/lists"
  end
end

# Add a new todo to a list
post "/lists/:list_id/todos" do
  @list_id = params[:list_id].to_i
  @list = load_list(@list_id)
  text = params[:todo].strip

  error = error_for_todo(text)
  if error
    session[:error] = error
    erb :list, layout: :layout
  else

    id_num = next_element_id(@list[:todos])
    @list[:todos] << { id: id_num, name: text, completed: false }

    session[:success] = "The todo was added."
    redirect "/lists/#{@list_id}"
  end
end

# Delete a todo from a list
post "/lists/:list_id/todos/:id/delete" do
  @list_id = params[:list_id].to_i
  @list = load_list(@list_id)

  todo_id = params[:id].to_i
  todo_name = @list[:todos].find { |todo| todo[:id] == todo_id }[:name]
  @list[:todos].reject! { |todo| todo[:id] == todo_id }

  if env["HTTP_X_REQUESTED_WITH"] == "XMLHttpRequest"
    status 204
  else
    session[:success] = "Todo \"#{todo_name}\" has been deleted."
    redirect "/lists/#{@list_id}"
  end
end

# Update the status of a todo
post "/lists/:list_id/todos/:id" do
  @list_id = params[:list_id].to_i
  @list = load_list(@list_id)

  todo_id = params[:id].to_i
  todo_name = @list[:todos].find { |todo| todo[:id] == todo_id }[:name]
  session[:success] = "Todo \"#{todo_name}\" has been updated."

  is_completed = params[:completed] == "true"
  todo = @list[:todos].find { |list_todo| list_todo[:id] == todo_id }
  todo[:completed] = is_completed

  redirect "/lists/#{@list_id}"
end

# Mark all todos as complete for a list
post "/lists/:id/complete_all" do
  @list_id = params[:id].to_i
  @list = load_list(@list_id)
  list_name = @list[:name]

  session[:success] = "All todos in list \"#{list_name}\" have been completed."
  @list[:todos].each { |todo| todo[:completed] = true }

  redirect "/lists/#{@list_id}"
end
