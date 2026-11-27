# frozen_string_literal: true

require "active_record"

# The PostgreSQL databases of the specs, and the few tables and models that several specs share. The models live
# under the AdapterSpecModels namespace so they do not mix with anything else; a spec makes its other models with
# define_model.
#
#   companies   the parent table of the specs' own models
#   orders      a parent with a composite primary key
#   users       a table that only the default database has
#   readings    the table of the secondary database
module AdapterSpecDatabase
  # The database the specs run against: the local PostgreSQL database pipeforge_test. No host, user
  # or password is given, so the Unix socket and the user who runs the specs are used (the PG
  # environment variables, such as PGHOST and PGUSER, apply, as they do in CI).
  CONNECTION_OPTIONS = {adapter: "postgresql", database: "pipeforge_test"}.freeze

  # A second database, for the models that are kept in another database than ActiveRecord::Base.
  SECONDARY_CONNECTION_OPTIONS = {adapter: "postgresql", database: "pipeforge_test_secondary"}.freeze

  # The tables created below, so a database that outlives the run starts clean.
  TABLES = %i[orders users companies].freeze
end

ActiveRecord::Base.establish_connection(AdapterSpecDatabase::CONNECTION_OPTIONS)
ActiveRecord::Schema.verbose = false

AdapterSpecDatabase::TABLES.each do |table|
  ActiveRecord::Base.connection.drop_table(table, if_exists: true, force: :cascade)
end

ActiveRecord::Schema.define do
  create_table(:companies) { |t| t.string :name }
  create_table(:users) { |t| t.string :email }
  create_table(:orders, primary_key: [:shop_id, :number]) do |t|
    t.integer :shop_id
    t.integer :number
  end
end

module AdapterSpecModels
  class Company < ActiveRecord::Base
    self.table_name = "companies"
  end

  class Order < ActiveRecord::Base
    self.table_name = "orders"
  end

  # A class with no table of its own, as ApplicationRecord is in an application.
  class AbstractModel < ActiveRecord::Base
    self.abstract_class = true
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

# The specs that save companies leave the table empty for the next example.
RSpec.configure do |config|
  config.after { AdapterSpecModels::Company.delete_all }
end
