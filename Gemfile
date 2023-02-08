source "https://rubygems.org"

ruby "3.2.0"

gem "erubis"
gem "sinatra", "~>2.2.3"
gem "sinatra-contrib"

gem "bcrypt"
gem "securerandom"

group :test do
  gem "minitest"
  gem "rack-test"
  gem 'simplecov', require: false
end

group :production do
  gem "pg"
  gem "puma"
end
