# frozen_string_literal: true

require_relative "model_record"
require_relative "schema_reader"

module Pipeforge
  # The ActiveRecord target for one target model: it reads the structure of the model's table, casts
  # values as the model would, builds the model's records, preloads their parents and runs a block in
  # a transaction. It reads no row of the target except the parent rows the model's own validation
  # needs. What is asked of one record (checking it, writing it) is answered by the
  # {ActiveRecordModelRecord} it returns.
  #
  # The target is named by its model class (+"User"+). The target finds the class among the models
  # that are loaded; it never loads any itself. The table is the model's own table.
  #
  # @example
  #   target = Pipeforge::ActiveRecordTarget.new(target_model_name: "User")
  #   target.schema.columns.map(&:name)  # => ["email", "company_id"]
  class ActiveRecordTarget
    # @param target_model_name [String] the name of a loaded model
    # @raise [TargetSchemaError] no loaded model has that name (+active_record_model_not_found+), or
    #   the table of the model does not exist (+target_table_not_found+)
    def initialize(target_model_name:)
      @model = find_model(target_model_name: target_model_name)
      reject_missing_table
      @enum_labels = read_enum_labels
    end

    # The labels of the model's enum for a column.
    #
    # @param column_name [String] a column of the table
    # @return [Array<String>, nil] the labels as text; nil when the model declares no enum for the column
    def enum_labels(column_name:)
      @enum_labels[column_name]
    end

    # The structure of the model's table: its columns that can be given a source column.
    #
    # @return [TargetSchema]
    def schema
      ActiveRecordSchemaReader.new(model: @model, enum_labels: @enum_labels).call
    end

    # Builds the model's unsaved record from the attributes. The text of a json or jsonb column is decoded as
    # JSON. A text that is not JSON and a value that is not a label of the column's enum are set aside for the
    # record to report.
    #
    # @param attributes [Hash{String => Object}] target column => value to load
    # @return [ActiveRecordModelRecord] the unsaved record, wrapped
    def build_record(attributes:)
      model_attributes = {}
      unknown_enum_labels = {}
      invalid_json_texts = {}

      attributes.each do |column_name, value|
        attribute_type = @model.type_for_attribute(column_name)

        # Only a text is decoded; nil and an object from a value mapping are assigned as they are.
        if json_text?(attribute_type: attribute_type, value: value)
          json_text_cast = cast_by_attribute_type(attribute_type: attribute_type, value: value)

          unless json_text_cast.castable
            invalid_json_texts[column_name] = value
            next
          end

          value = json_text_cast.cast_value
        end

        labels = enum_labels(column_name: column_name)

        if labels.nil? || value.nil?
          model_attributes[column_name] = value
          next
        end

        # ActiveRecord raises on an enum label it does not know, so a value that is not a label (a value the
        # database stores for one included) is set aside and reported by the record as value_not_allowed.
        label = value.to_s

        if labels.include?(label)
          model_attributes[column_name] = label
        else
          unknown_enum_labels[column_name] = label
        end
      end

      ActiveRecordModelRecord.new(
        record: @model.new(model_attributes),
        unknown_enum_labels: unknown_enum_labels,
        invalid_json_texts: invalid_json_texts
      )
    end

    # Reads a value as the column's type would: what the model would load (the cast value, a Ruby object) and
    # the same data in plain JSON types (the json value). It reads no row and writes nothing. The value of an
    # enum column is given back as it is.
    #
    # @param column_name [String] a column of the table
    # @param value [String, Hash, Array, Object] a value from the file (a non-empty text) or from a value
    #   mapping, as it is
    # @return [CastResult] the cast value and the json value of a value the type can cast (both are nil for the
    #   JSON null), or {CastResult::NOT_CASTABLE} for a value it cannot cast; for an enum column, the value as
    #   it is
    def cast_value(column_name:, value:)
      # The cast of an enum type turns a value the database stores for a label into that label (1 into
      # "placed") and leaves its text ("1") alone, which would show the same value in two ways.
      unless enum_labels(column_name: column_name).nil?
        return castable_cast_result(cast_value: value)
      end

      cast_by_attribute_type(attribute_type: @model.type_for_attribute(column_name), value: value)
    end

    # Runs the block in one transaction on the connection of the table's model; with +rollback_at_end+
    # the transaction is undone when the block ends, so nothing the block wrote is kept.
    #
    # @param rollback_at_end [Boolean] undo everything the block wrote when it ends
    # @yield the work to do inside the transaction
    # @return [Object] the block's result
    def transaction(rollback_at_end:, &block)
      result = nil

      # The model's own connection, so a model kept in another database is written to that database.
      @model.transaction do
        result = block.call
        raise ActiveRecord::Rollback if rollback_at_end
      end

      # Kept in a variable because a rolled-back transaction returns nil.
      result
    end

    # Loads the parents that the records need, with one query for each +belongs_to+ association (for each
    # parent class of a polymorphic one).
    #
    # @param records [Array<ActiveRecordModelRecord>] the records built for one chunk
    # @return [void]
    def preload_parents(records:)
      unsaved_records = []
      records.each { |model_record| unsaved_records << model_record.record }

      @model.reflect_on_all_associations(:belongs_to).each do |reflection|
        # One query for each association, so the model's validation does not query the parent of each record.
        ActiveRecord::Associations::Preloader.new(records: unsaved_records, associations: reflection.name).call
      end
    end

    private

    # The labels of every enum the model declares, by column name. The model's enums do not change, so they are
    # read once.
    def read_enum_labels
      labels_by_column_name = {}

      @model.defined_enums.each do |column_name, enum_mapping|
        # A label is text; one that ActiveRecord keeps as a number is read as its text.
        labels_by_column_name[column_name] = enum_mapping.keys.map(&:to_s)
      end

      labels_by_column_name
    end

    # The loaded model with that name. An abstract class is not a model of a table, so it is not found.
    def find_model(target_model_name:)
      model = ActiveRecord::Base.descendants.find do |candidate|
        candidate.name == target_model_name && !candidate.abstract_class?
      end
      return model unless model.nil?

      raise TargetSchemaError.single(
        code: :active_record_model_not_found,
        message: "no loaded model is named #{target_model_name}; the model must be loaded before the schema is read",
        model_name: target_model_name
      )
    end

    def reject_missing_table
      # The connection of the model, because a model can use another database than ActiveRecord::Base.
      table_exists = @model.with_connection do |connection|
        connection.data_source_exists?(@model.table_name)
      end
      return if table_exists

      raise TargetSchemaError.single(
        code: :target_table_not_found,
        message: "table #{@model.table_name} of #{@model.name} does not exist in the database",
        table_name: @model.table_name
      )
    end

    # Casts a value with the attribute type of a column; the text of a json or jsonb column is decoded as JSON.
    #
    # @return [CastResult] the answer of {#cast_value}: {CastResult::NOT_CASTABLE} for a value the type cannot
    #   cast or a text that is not JSON
    def cast_by_attribute_type(attribute_type:, value:)
      if json_text?(attribute_type: attribute_type, value: value)
        cast_json_text(text: value)
      else
        cast_with_attribute_type(attribute_type: attribute_type, value: value)
      end
    end

    # A json or jsonb text is decoded as JSON; a text that is not JSON cannot be cast.
    def cast_json_text(text:)
      # decode, not deserialize: deserialize turns a parse error into nil, the same as the text null. cast
      # would keep the String, which the column then stores as a JSON string.
      castable_cast_result(cast_value: ActiveSupport::JSON.decode(text))
    rescue JSON::ParserError
      CastResult::NOT_CASTABLE
    end

    # Casts a value that is not the text of a json or jsonb column.
    def cast_with_attribute_type(attribute_type:, value:)
      # The cast is lenient: abc in an integer column is 0.
      loaded_value = attribute_type.cast(value)

      # ActiveRecord answers nil for a text it cannot read, such as a day that is not in the calendar.
      return CastResult::NOT_CASTABLE if loaded_value.nil?

      castable_cast_result(cast_value: loaded_value)
    end

    def castable_cast_result(cast_value:)
      CastResult.new(castable: true, cast_value: cast_value, json_value: cast_value.as_json)
    end

    # Whether a value is the text of a json or jsonb column, which is read as JSON.
    def json_text?(attribute_type:, value:)
      json_column?(attribute_type: attribute_type) && value.is_a?(String)
    end

    def json_column?(attribute_type:)
      [:json, :jsonb].include?(attribute_type.type)
    end
  end
end
