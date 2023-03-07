require "pg"

class DatabasePersistence
  def initialize(logger = nil)
    @db = if Sinatra::Base.production?
            PG.connect(ENV.fetch('RAILWAY_DATABASE_URL', nil))
          else
            PG.connect(dbname: 'musicnotes')
          end
    @logger = logger
  end

  def query(statement, *params)
    @logger.info "#{statement}: #{params}" unless Sinatra::Base.test?
    @db.exec_params(statement, params)
  end

  def delete_user(name)
    sql = "DELETE FROM users WHERE name = $1"
    query(sql, name)
  end

  def create_user_checkboxes(name)
    user_id = find_student_id(name)
    sql = "INSERT INTO checkboxes (day, user_id) VALUES "

    WEEKDAYS.each_with_index do |day, idx|
      break if idx == WEEKDAYS.size - 1
      sql << "('#{day.downcase}', $#{idx + 1}), "
    end
    sql << "('#{WEEKDAYS.last.downcase}', $#{WEEKDAYS.size})"

    ids = [user_id] * WEEKDAYS.size
    query(sql, *ids)
  end

  def create_user(name, pass)
    sql = "INSERT INTO users (name, password) VALUES ($1, $2)"
    query(sql, name, BCrypt::Password.create(pass))

    create_user_checkboxes(name)
  end

  # rubocop:disable Metrics/MethodLength
  def create_test_users(test_user_hash)
    sql_values = []
    sql_params = []

    placeholder = 1
    test_user_hash.each do |user, pass|
      sql_values << "($#{placeholder}, $#{placeholder + 1})"
      sql_params << user
      sql_params << pass
      placeholder += 2
    end

    sql = "INSERT INTO users (name, password) VALUES " << sql_values.join(', ')
    query(sql, *sql_params)

    test_user_hash.keys.each { |name| create_user_checkboxes(name) }
  end
  # rubocop:enable Metrics/MethodLength

  def delete_test_users(test_user_hash)
    sql_values = []
    sql_params = []

    placeholder = 1
    test_user_hash.keys.each do |name|
      sql_values << "name = $#{placeholder}"
      sql_params << name
      placeholder += 1
    end

    sql = "DELETE FROM users WHERE " << sql_values.join(' OR ')
    query(sql, *sql_params)
  end

  def find_student_id(name)
    sql = "SELECT id FROM users WHERE name = $1"
    result = query(sql, name)
    result.field_values("id").first
  end

  def reset_checkboxes(name)
    sql = <<~SQL
      UPDATE checkboxes
        SET checked = false
        WHERE user_id IN (
          SELECT id
          FROM users
          WHERE name = $1
        )
    SQL

    query(sql, name)
  end

  def find_all_user_names
    sql = "SELECT name FROM users"
    query(sql)
  end

  def find_all_user_credentials
    sql = "SELECT name, password FROM users"
    query(sql)
  end

  def tuple_to_checkbox_hash(result)
    result.map do |tuple|
      { day: tuple["day"], checked: tuple["checked"] == "t" }
    end
  end

  def load_user_checkboxes(name)
    sql = <<~SQL
    SELECT chs.day, chs.checked
       FROM checkboxes chs
       JOIN users ON chs.user_id = users.id
       WHERE users.name = $1
       ORDER BY chs.id
    SQL

    result = query(sql, name)
    tuple_to_checkbox_hash(result)
  end

  def find_last_clicked_none_checked(checkboxes)
    checkboxes.select { |hash| hash[:checked] }
  end

  def find_last_clicked_some_checked(checkboxes, params)
    checkboxes.select do |hash|
      (params['checkbox_group'].include?(hash[:day]) && !hash[:checked]) ||
        (!params['checkbox_group'].include?(hash[:day]) && hash[:checked])
    end
  end

  def update_checkboxes(params, name, student_id)
    checkboxes = load_user_checkboxes(name)

    last_clicked_box = if params['checkbox_group'].nil?
                         find_last_clicked_none_checked(checkboxes)
                       else
                         find_last_clicked_some_checked(checkboxes, params)
                       end.first

    sql = "UPDATE checkboxes SET checked = $1 WHERE day = $2 AND user_id = $3"
    query(sql, !last_clicked_box[:checked], last_clicked_box[:day], student_id)
  end
end
