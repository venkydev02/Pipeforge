# frozen_string_literal: true

require "active_record"

# Creates, inside one example, a small real table and a real ActiveRecord model over it, so an example shows the
# columns it reads right where it uses them. The table is dropped at the end of the example, so the next example can
# create a table of the same name with other columns. Nothing is replaced by a double: it is the same ActiveRecord and
# the same database as the other specs of the adapter. The table is an ordinary one and not a temporary one, because
# ActiveRecord does not find a temporary table of PostgreSQL among the tables of the database, and so reads no primary
# key from it. After the example the name of the model answers nil, so a search of the loaded classes by name (as the
# target does) cannot find a class that an earlier example left behind.
#
#   model = define_model(name: "ModelWithoutPrimaryKey", primary_key: false, columns: ->(table) { table.string :label })
#   model.columns_hash.keys   # => ["label"]
module DefineModelHelper
  # @param name [String] the name of the model, which says the fact the example shows ("ModelWithEnum"); the table
  #   is named like it ("model_with_enum")
  # @param primary_key [Boolean, Array<Symbol>] true for the usual +id+ column, false for no key, or the names of
  #   the columns of a composite key (which +columns+ declares)
  # @param table [Boolean] false for a model whose table does not exist
  # @param columns [Proc, nil] given the table definition, declares the columns
  # @yield the body of the model class: +attribute+, +enum+, +belongs_to+ and the like
  # @return [Class] the model, named +"AdapterSpecModels::<name>"+
  def define_model(name:, primary_key: true, table: true, columns: nil, &declarations)
    table_name = name.underscore
    connection = ActiveRecord::Base.connection

    table_options = {}
    table_options[:id] = false if primary_key == false
    table_options[:primary_key] = primary_key if primary_key.is_a?(Array)

    # A table of this name left by a run that stopped before it could drop it.
    connection.drop_table(table_name, if_exists: true)
    connection.create_table(table_name, **table_options) { |definition| columns&.call(definition) } if table
    # ActiveRecord keeps the columns of a table by its name, and an earlier example may have used the same name.
    connection.schema_cache.clear_data_source_cache!(table_name)

    model = Class.new(ActiveRecord::Base)
    model.table_name = table_name
    model_name = "AdapterSpecModels::#{name}"
    model.define_singleton_method(:name) { model_name }
    model.class_eval(&declarations) unless declarations.nil?

    @defined_models = [] if @defined_models.nil?
    @defined_models << model

    model
  end
end

RSpec.configure do |config|
  config.include DefineModelHelper

  config.after do
    next if @defined_models.nil?

    connection = ActiveRecord::Base.connection
    @defined_models.each do |model|
      connection.drop_table(model.table_name, if_exists: true)
      connection.schema_cache.clear_data_source_cache!(model.table_name)
      model.define_singleton_method(:name) { nil }
    end
  end
end
