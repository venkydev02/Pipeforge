# frozen_string_literal: true

require "active_record"

# A database with a few tables and models, for the specs of the ActiveRecord adapter: PostgreSQL
# (see AdapterSpecDatabase). The tables and models are created once, when the specs load, and live
# under the AdapterSpecModels namespace so they do not mix with anything else.
#
#   users       a typical table: sizes, a decimal, a foreign key, an ignored column, a generated
#               column, timestamps
#   vehicles    single table inheritance (Vehicle, with Car and Truck below it)
#   notes       two unrelated models on one table (Note and Memo)
#   orphans     a table that no model uses
#   readings    a table of the secondary database, which a model of its own reads (and a model of that
#               database named like users, a table that database does not have)
#   comments    a polymorphic association (not described as a foreign key)
#   order_lines a composite foreign key (not described as a foreign key)
#   invoices    NOT NULL columns with and without a default (a value and a function), and a
#               NOT NULL foreign key whose association is optional in the model
#   receipts    NOT NULL timestamps on a model that does not record timestamps
#   tickets     a column the model declares with another type than the table
#   shipments   enums (stored as a number and as text, with and without a default in the
#               table) and a column whose default is set only in the model
#   events      a date and a datetime column, for the formats the model reads
#   measurements a single precision float (limit 24) next to a double precision one
#   quantities  an integer with no size (4 bytes) next to a bigint (8 bytes)
#   profiles    a json column and a jsonb column, for the text a file holds in them
#   counters    an unsigned integer attribute (the type MySQL gives an unsigned column) on a wider table column, next to a signed one
#   memberships a model with validations: presence, uniqueness, length, numericality, an enum
#               that must be present, a required parent and a mistake on the record as a whole
#   accounts    a model with no validations, on a table that refuses what the model does not check:
#               a repeated email (unique index), an empty email (NOT NULL) and a company that
#               does not exist (foreign key); a callback stops the save of one nickname
module AdapterSpecDatabase
  # The database the specs run against: the local PostgreSQL database pipeforge_test. No host, user
  # or password is given, so the Unix socket and the user who runs the specs are used (the PG
  # environment variables, such as PGHOST and PGUSER, apply, as they do in CI).
  CONNECTION_OPTIONS = {adapter: "postgresql", database: "pipeforge_test"}.freeze

  # A second database, for the models that are kept in another database than ActiveRecord::Base.
  SECONDARY_CONNECTION_OPTIONS = {adapter: "postgresql", database: "pipeforge_test_secondary"}.freeze

  # The tables created below, so a database that outlives the run starts clean.
  TABLES = %i[
    profiles quantities playlists accounts memberships counters measurements events shipments tickets receipts invoices
    order_lines orders comments orphans notes vehicles users companies
  ].freeze
end

ActiveRecord::Base.establish_connection(AdapterSpecDatabase::CONNECTION_OPTIONS)
ActiveRecord::Schema.verbose = false

AdapterSpecDatabase::TABLES.each do |table|
  ActiveRecord::Base.connection.drop_table(table, if_exists: true, force: :cascade)
end

ActiveRecord::Schema.define do
  create_table(:companies) { |t| t.string :name }

  create_table(:users) do |t|
    t.string :email, limit: 255, null: false
    t.integer :age, limit: 2
    t.decimal :balance, precision: 10, scale: 2
    t.text :bio
    t.boolean :active, default: true
    t.references :company
    t.string :legacy_code
    t.virtual :shout, type: :string, as: "upper(email)", stored: false
    t.timestamps
  end

  create_table(:vehicles) { |t| t.string :type, :wheels }
  create_table(:notes) { |t| t.string :title }
  create_table(:orphans) { |t| t.string :name }
  create_table(:comments) do |t|
    t.integer :commentable_id
    t.string :commentable_type
  end
  create_table(:orders, primary_key: [:shop_id, :number]) do |t|
    t.integer :shop_id
    t.integer :number
  end
  create_table(:order_lines) do |t|
    t.integer :shop_id
    t.integer :order_number
  end
  create_table(:invoices) do |t|
    t.string :number, null: false
    t.string :status, null: false, default: "open"
    t.references :company, null: false
    t.datetime :issued_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
    t.timestamps
  end
  create_table(:receipts) do |t|
    t.string :number, null: false
    t.timestamps
  end
  create_table(:tickets) { |t| t.string :rank }
  create_table(:shipments) do |t|
    t.integer :status, null: false, default: 0
    t.string :kind, null: false, default: "retail"
    t.integer :priority, null: false
    t.string :channel, null: false
    t.string :note
  end
  create_table(:events) do |t|
    t.date :starts_on
    t.datetime :starts_at
  end
  create_table(:measurements) do |t|
    t.float :ratio, limit: 24
    t.float :weight
  end
  create_table(:counters) do |t|
    # Wider than the 2 bytes of the model's unsigned attribute: PostgreSQL has no unsigned integer, so a
    # 2-byte column would refuse the values above 32767 that the attribute accepts.
    t.integer :hits
    t.integer :misses, limit: 2
  end
  create_table(:quantities) do |t|
    t.integer :plain_count
    t.bigint :big_count
  end
  create_table(:profiles) do |t|
    t.string :name
    t.json :settings
    t.jsonb :extras
  end
  create_table(:memberships) do |t|
    t.string :email, limit: 20, null: false
    t.integer :seats, limit: 2
    t.decimal :fee, precision: 5, scale: 2
    t.integer :tier
    t.references :company
  end
  create_table(:accounts) do |t|
    t.string :email, null: false
    t.string :nickname
    t.references :company, foreign_key: true
  end
  add_index :accounts, :email, unique: true

  create_table(:playlists) do |t|
    t.string :title
    t.column :track_ids, :integer, array: true
    t.column :tags, :text, array: true
  end
end

module AdapterSpecModels
  class Company < ActiveRecord::Base
    self.table_name = "companies"
  end

  class User < ActiveRecord::Base
    self.table_name = "users"
    self.ignored_columns = ["legacy_code"]
    belongs_to :company, class_name: "AdapterSpecModels::Company"
  end

  class Vehicle < ActiveRecord::Base
    self.table_name = "vehicles"
  end

  class Car < Vehicle; end

  class Truck < Vehicle; end

  class Note < ActiveRecord::Base
    self.table_name = "notes"
  end

  class Memo < ActiveRecord::Base
    self.table_name = "notes"
  end

  class Comment < ActiveRecord::Base
    self.table_name = "comments"
    belongs_to :commentable, polymorphic: true
  end

  # The same table, with the parent required (what a Rails application has by default).
  class CommentWithRequiredParent < ActiveRecord::Base
    self.table_name = "comments"
    belongs_to :commentable, polymorphic: true, optional: false
  end

  class Order < ActiveRecord::Base
    self.table_name = "orders"
  end

  class Invoice < ActiveRecord::Base
    self.table_name = "invoices"
    belongs_to :company, class_name: "AdapterSpecModels::Company", optional: true
  end

  class Receipt < ActiveRecord::Base
    self.table_name = "receipts"
    self.record_timestamps = false
  end

  class Ticket < ActiveRecord::Base
    self.table_name = "tickets"
    attribute :rank, :integer
  end

  class Shipment < ActiveRecord::Base
    self.table_name = "shipments"
    enum :status, {draft: 0, placed: 1, shipped: 2}
    enum :kind, {retail: "retail", wholesale: "wholesale"}
    enum :priority, {low: 0, high: 1}
    attribute :channel, :string, default: "web"
  end

  class OrderLine < ActiveRecord::Base
    self.table_name = "order_lines"
    belongs_to :order, class_name: "AdapterSpecModels::Order",
      foreign_key: [:shop_id, :order_number], primary_key: [:shop_id, :number]
  end

  class Event < ActiveRecord::Base
    self.table_name = "events"
  end

  class Measurement < ActiveRecord::Base
    self.table_name = "measurements"
  end

  class Counter < ActiveRecord::Base
    self.table_name = "counters"
    attribute :hits, ActiveRecord::Type::UnsignedInteger.new(limit: 2)
  end

  class Quantity < ActiveRecord::Base
    self.table_name = "quantities"
  end

  class Membership < ActiveRecord::Base
    self.table_name = "memberships"
    enum :tier, {basic: 0, pro: 1}
    belongs_to :company, class_name: "AdapterSpecModels::Company", optional: false
    validates :email, presence: true, uniqueness: true, length: {maximum: 20}
    validates :tier, presence: true
    validates :seats, numericality: {less_than: 100_000}, allow_nil: true
    validate :email_not_closed
    before_validation :strip_email

    def strip_email
      self.email = email.strip unless email.nil?
    end

    def email_not_closed
      errors.add(:base, "signups are closed for this email") if email == "closed@example.com"
    end
  end

  # A class with no table of its own, as ApplicationRecord is in an application.
  class AbstractModel < ActiveRecord::Base
    self.abstract_class = true
  end

  class Account < ActiveRecord::Base
    self.table_name = "accounts"
    before_save { throw :abort if nickname == "halt" }
  end

  class Playlist < ActiveRecord::Base
    self.table_name = "playlists"
  end

  class Profile < ActiveRecord::Base
    self.table_name = "profiles"
    validates :name, presence: true
  end

  # A model that also requires its json column.
  class ProfileWithRequiredSettings < ActiveRecord::Base
    self.table_name = "profiles"
    validates :name, :settings, presence: true
  end

  # Models that use another database than ActiveRecord::Base: the secondary database. Its only
  # table is readings.
  class SecondaryDatabaseRecord < ActiveRecord::Base
    self.abstract_class = true
    establish_connection(AdapterSpecDatabase::SECONDARY_CONNECTION_OPTIONS)
  end

  class ModelInSecondaryDatabase < SecondaryDatabaseRecord
    self.table_name = "readings"
  end

  # A model of the secondary database whose table is named like one of the default database, which the secondary database does not have.
  class ModelWithTableOnlyInDefaultDatabase < SecondaryDatabaseRecord
    self.table_name = "users"
  end
end

AdapterSpecModels::SecondaryDatabaseRecord.with_connection do |connection|
  connection.drop_table(:readings, if_exists: true)
  connection.create_table(:readings) { |t| t.string :label }
end

# The specs that save rows leave the tables empty for the next example.
RSpec.configure do |config|
  config.after do
    AdapterSpecModels::Account.delete_all
    AdapterSpecModels::Membership.delete_all
    AdapterSpecModels::Company.delete_all
    AdapterSpecModels::Profile.delete_all
  end
end
