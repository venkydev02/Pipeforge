# frozen_string_literal: true

require "active_record"

# An in-memory SQLite database with a few tables and models, for the specs of the ActiveRecord
# adapter. The tables and models are created once, when the specs load, and live under the
# AdapterSpecModels namespace so they do not mix with anything else.
#
#   users       a typical table: sizes, a decimal, a foreign key, an ignored column, a generated
#               column, timestamps
#   contacts    a foreign key that is optional
#   leads       a foreign key with no setting (the model default decides)
#   vehicles    single table inheritance (Vehicle, with Car and Truck below it)
#   notes       two unrelated models on one table (Note and Memo)
#   orphans     a table with no model
#   comments    a polymorphic association (not described as a foreign key)
#   order_lines a composite foreign key (not described as a foreign key)
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

  create_table(:contacts) { |t| t.references :company }
  create_table(:leads) { |t| t.references :company }
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
end

module AdapterSpecModels
  class Company < ActiveRecord::Base
    self.table_name = "companies"
  end

  class User < ActiveRecord::Base
    self.table_name = "users"
    self.belongs_to_required_by_default = true
    self.ignored_columns = ["legacy_code"]
    belongs_to :company, class_name: "AdapterSpecModels::Company"
  end

  class Contact < ActiveRecord::Base
    self.table_name = "contacts"
    belongs_to :company, class_name: "AdapterSpecModels::Company", optional: true
  end

  class Lead < ActiveRecord::Base
    self.table_name = "leads"
    self.belongs_to_required_by_default = false
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

  class OrderLine < ActiveRecord::Base
    self.table_name = "order_lines"
    belongs_to :order, class_name: "AdapterSpecModels::Order",
      foreign_key: [:shop_id, :order_number], primary_key: [:shop_id, :number]
  end
end
