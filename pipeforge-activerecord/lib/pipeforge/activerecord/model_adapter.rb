# frozen_string_literal: true

require_relative "model_record"

module Pipeforge
  # The ActiveRecord adapter's object for one target table: it builds the application model's
  # records and preloads their parents. It reads no row of the target except the parent rows the
  # model's own validation needs. What is asked of one record is answered by the
  # {ActiveRecordModelRecord} it returns.
  class ActiveRecordModelAdapter
    # @param model [Class] the ActiveRecord model of the target table
    def initialize(model:)
      @model = model
    end

    # Instantiates the model from the attributes.
    #
    # @param attributes [Hash{String => Object}] target column => value to load
    # @return [ActiveRecordModelRecord] the unsaved record, wrapped
    def build_record(attributes:)
      model_attributes = {}
      unknown_enum_labels = {}

      attributes.each do |column_name, value|
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

      ActiveRecordModelRecord.new(record: @model.new(model_attributes), unknown_enum_labels: unknown_enum_labels)
    end

    # The value the model would load for a text in a column: the text cast by the attribute type of the
    # column, or nil when the type cannot read the text. It reads no row and writes nothing.
    #
    # @param column_name [String] a column of the table
    # @param text [String] a non-empty value from the file
    # @return [Object, nil] the cast value, or nil when the type cannot read the text
    def cast_text(column_name:, text:)
      # The cast is lenient: abc in an integer column is 0.
      @model.type_for_attribute(column_name).cast(text)
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
