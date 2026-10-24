# frozen_string_literal: true

require "active_record"

# An in-memory SQLite database with a few tables and models, for the specs of the ActiveRecord
# adapter. The tables and models are created once, when the specs load, and live under the
# AdapterSpecModels namespace so they do not mix with anything else.
#
#   users       a typical table: sizes, a decimal, a foreign key, an ignored column, a generated
#               column, timestamps
#   vehicles    single table inheritance (Vehicle, with Car and Truck below it)
#   notes       two unrelated models on one table (Note and Memo)
#   orphans     a table with no model
#   comments    a polymorphic association (not described as a foreign key)
#   order_lines a composite foreign key (not described as a foreign key)
#   invoices    NOT NULL columns with and without a default (a value and a function), and a
#               NOT NULL foreign key whose association is optional in the model
#   receipts    NOT NULL timestamps on a model that does not record timestamps
#   tickets     a column the model declares with another type than the table
#   shipments   enums (stored as a number and as text, with and without a default in the
#               table) and a column whose default is set only in the model
ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
ActiveRecord::Schema.verbose = false

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
end
