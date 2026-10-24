# frozen_string_literal: true

# Seeds a SQLite database with sample tables and records, for trying the engine by hand during
# development. It deletes and recreates the database each time it runs, so the data is always the
# same. Everything in it is invented.
#
# Run it on its own:
#
#   bundle exec ruby script/seed_development.rb
#
# Or open a Ruby console with the database seeded and the models loaded (see script/console).
#
# The tables are the target and the table its foreign key refers to:
#   users      the target table, 10 rows; has a foreign key to companies, an ignored
#              column (legacy_code) and a generated column (full_name), which the engine leaves
#              out of the target schema
#   companies  the parent table, 5 rows
#
# Sample source files that match these tables are in script/sample_data.

require "fileutils"
require "pipeforge/activerecord"

DATABASE_PATH = File.expand_path("../tmp/development.sqlite3", __dir__)

FileUtils.mkdir_p(File.dirname(DATABASE_PATH))
# SQLite keeps a database in up to three files: the database itself and its -wal and -shm files.
FileUtils.rm_f(Dir["#{DATABASE_PATH}*"])

ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: DATABASE_PATH)
ActiveRecord::Schema.verbose = false

ActiveRecord::Schema.define do
  create_table :companies do |t|
    t.string :name, null: false
    t.string :code, null: false
    t.timestamps
  end

  create_table :users do |t|
    t.string :email, limit: 255, null: false
    t.string :first_name, limit: 50, null: false
    t.string :last_name, limit: 50, null: false
    t.integer :age, limit: 2
    t.decimal :balance, precision: 10, scale: 2, default: 0
    t.string :status, limit: 20, default: "active"
    t.boolean :active, default: true
    t.text :bio
    t.references :company, null: false
    t.string :legacy_code
    t.virtual :full_name, type: :string, as: "first_name || ' ' || last_name", stored: false
    t.timestamps
  end
end

module Sample
  class Company < ActiveRecord::Base
    self.table_name = "companies"
  end

  class User < ActiveRecord::Base
    self.table_name = "users"
    self.ignored_columns = ["legacy_code"]
    belongs_to :company, class_name: "Sample::Company"
  end
end

# Ten first names and ten last names: user number 1 is the first of each, number 2 the second
# of each, and so on, so no two users have the same name.
FIRST_NAMES = %w[Ann Ben Cara Dan Eve Finn Gia Hugo Iris Jon].freeze
LAST_NAMES = %w[Lee Khan Silva Novak Brown Rossi Singh Garcia Meyer Costa].freeze
COMPANY_NAMES = ["Acme Corp", "Globex", "Initech", "Umbrella Ltd", "Hooli"].freeze
STATUSES = %w[active inactive suspended].freeze

companies = []
COMPANY_NAMES.each_with_index do |name, index|
  companies << Sample::Company.create!(name: name, code: format("C%03d", index + 1))
end

FIRST_NAMES.each_with_index do |first_name, index|
  last_name = LAST_NAMES[index]

  Sample::User.create!(
    email: "#{first_name.downcase}.#{last_name.downcase}@example.com",
    first_name: first_name,
    last_name: last_name,
    age: 21 + index * 4,
    balance: index * 125.5,
    status: STATUSES[index % STATUSES.size],
    active: index.even?,
    bio: "Sample bio for #{first_name} #{last_name}.",
    company: companies[index % companies.size]
  )
end

puts "Seeded #{DATABASE_PATH}"
puts "  companies: #{Sample::Company.count}, users: #{Sample::User.count}"
