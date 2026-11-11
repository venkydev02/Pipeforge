# frozen_string_literal: true

require_relative "model_record"

module Pipeforge
  # The ActiveRecord adapter's object for one target table: it builds the application model's
  # records, preloads their parents and runs a block in a transaction. It reads no row of the target
  # except the parent rows the model's own validation needs. What is asked of one record (checking
  # it, writing it) is answered by the {ActiveRecordModelRecord} it returns.
  class ActiveRecordModelAdapter
    # @param model [Class] the ActiveRecord model of the target table
    def initialize(model:)
      @model = model
    end

    # Instantiates the model from the attributes. The text of a json or jsonb column is read as JSON; a text
    # that is not JSON, and an enum label the model does not know, are not given to the model: the record
    # reports them.
    #
    # @param attributes [Hash{String => Object}] target column => value to load
    # @return [ActiveRecordModelRecord] the unsaved record, wrapped
    def build_record(attributes:)
      model_attributes = {}
      unknown_enum_labels = {}
      invalid_json_texts = {}

      attributes.each do |column_name, value|
        # Only a text is read as JSON; nil (an empty cell) and an object a value mapping gave are assigned as they are.
        if json_column?(column_name: column_name) && value.is_a?(String)
          json_reading = read_json(text: value)

          unless json_reading[:casted]
            # The record cannot hold a text that is not JSON, so it is set aside and reported by the record
            # as value_not_json.
            invalid_json_texts[column_name] = value
            next
          end

          value = json_reading[:cast_value]
        end

        enum_mapping = @model.defined_enums[column_name]

        if enum_mapping.nil? || value.nil?
          model_attributes[column_name] = value
          next
        end

        # ActiveRecord raises on an enum label it does not know, so such a label is set aside and reported
        # by the record as value_not_allowed. A stored value written as text ("1") is cast to the stored type.
        enum_value = known_enum_value(enum_mapping: enum_mapping, value: value)

        if enum_value.nil?
          unknown_enum_labels[column_name] = value.to_s
        else
          model_attributes[column_name] = enum_value
        end
      end

      ActiveRecordModelRecord.new(
        record: @model.new(model_attributes),
        unknown_enum_labels: unknown_enum_labels,
        invalid_json_texts: invalid_json_texts
      )
    end

    # What the model would load for a text in a column: the text cast by the attribute type of the column.
    # For a json or jsonb column that is the object, list or string the text describes. It reads no row and
    # writes nothing.
    #
    # @param column_name [String] a column of the table
    # @param text [String] a non-empty value from the file
    # @return [Hash] +{casted: true, cast_value: <the cast value>}+ when the type can read the text (the
    #   +cast_value+ is nil for the JSON null), and +{casted: false}+ when it cannot
    def cast_text(column_name:, text:)
      return read_json(text: text) if json_column?(column_name: column_name)

      # The cast is lenient: abc in an integer column is 0.
      cast_value = @model.type_for_attribute(column_name).cast(text)
      return {casted: false} if cast_value.nil?

      {casted: true, cast_value: cast_value}
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

    # Loads the parents that the records need, with one query for each +belongs_to+ association. A
    # polymorphic association and a composite key are left alone.
    #
    # @param records [Array<ActiveRecordModelRecord>] the records built for one chunk
    # @return [void]
    def preload_parents(records:)
      unsaved_records = []
      records.each { |model_record| unsaved_records << model_record.record }

      @model.reflect_on_all_associations(:belongs_to).each do |reflection|
        # The preloader needs one foreign key column and one parent class.
        next if reflection.polymorphic?
        next unless reflection.foreign_key.is_a?(String)

        # One query for each association, so the model's validation does not query the parent of each record.
        ActiveRecord::Associations::Preloader.new(records: unsaved_records, associations: reflection.name).call
      end
    end

    private

    # Reads a text as JSON.
    #
    # @param text [String] the text for a json or jsonb column
    # @return [Hash] +{casted: true, cast_value: <what the text describes>}+ when the text is JSON (the
    #   +cast_value+ is nil for the JSON null), and +{casted: false}+ when it is not
    def read_json(text:)
      # decode, not the column type's deserialize: deserialize hides a parse error as nil, the same nil as for the
      # text null, so the two could not be told apart. cast would keep the text as a String, which the column
      # then stores as a JSON string.
      {casted: true, cast_value: ActiveSupport::JSON.decode(text)}
    rescue JSON::ParserError
      {casted: false}
    end

    # Whether the column is a json or jsonb column.
    def json_column?(column_name:)
      [:json, :jsonb].include?(@model.type_for_attribute(column_name).type)
    end

    # The label when the value is a label of the enum, the stored value when it is a stored value
    # written as text, and nil when it is neither.
    def known_enum_value(enum_mapping:, value:)
      text = value.to_s
      return text if enum_mapping.key?(text)

      enum_mapping.each_value do |stored_value|
        return stored_value if stored_value.to_s == text
      end

      nil
    end
  end
end
