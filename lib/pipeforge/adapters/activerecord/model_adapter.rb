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

    # Builds the model's unsaved record from the attributes. The text of a json or jsonb column is decoded as
    # JSON. A text that is not JSON and an enum label the model does not know are set aside for the record to
    # report.
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
        if json_column?(attribute_type: attribute_type) && value.is_a?(String)
          json_text_cast = cast_by_attribute_type(attribute_type: attribute_type, text: value)

          unless json_text_cast.castable
            invalid_json_texts[column_name] = value
            next
          end

          value = json_text_cast.cast_value
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

    # Reads a text as the column's type would: what the model would load (the cast value, a Ruby object) and
    # the same data in plain JSON types (the json value). It reads no row and writes nothing.
    #
    # @param column_name [String] a column of the table
    # @param text [String] a non-empty value from the file
    # @return [CastResult] the cast value and the json value of a text the type can cast (both are nil for the
    #   JSON null), or {CastResult::NOT_CASTABLE} for a text it cannot cast
    def cast_text(column_name:, text:)
      cast_by_attribute_type(attribute_type: @model.type_for_attribute(column_name), text: text)
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

    # Casts a text with the attribute type of a column; a json or jsonb text is decoded as JSON.
    #
    # @return [CastResult] the answer of {#cast_text}: {CastResult::NOT_CASTABLE} for a text the type cannot
    #   cast or a text that is not JSON
    def cast_by_attribute_type(attribute_type:, text:)
      if json_column?(attribute_type: attribute_type)
        cast_json_text(text: text)
      else
        cast_non_json_text(attribute_type: attribute_type, text: text)
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

    # Casts a text of a column that is not a json or jsonb column.
    def cast_non_json_text(attribute_type:, text:)
      # The cast is lenient: abc in an integer column is 0.
      cast_value = attribute_type.cast(text)

      # ActiveRecord answers nil for a text it cannot read, such as a day that is not in the calendar.
      return CastResult::NOT_CASTABLE if cast_value.nil?

      castable_cast_result(cast_value: cast_value)
    end

    def castable_cast_result(cast_value:)
      CastResult.new(castable: true, cast_value: cast_value, json_value: cast_value.as_json)
    end

    def json_column?(attribute_type:)
      [:json, :jsonb].include?(attribute_type.type)
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
