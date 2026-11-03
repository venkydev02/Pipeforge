# frozen_string_literal: true

module Pipeforge
  # Applies the consumer's column mapping to one source row. It does the header mapping (which source
  # column feeds each target column) and the value mapping, and nothing else.
  class RowTransformer
    # @param mapped_columns [Hash{String => Hash}] target column => {source_column:, value_mapping:};
    #   the keys of a value mapping are text, as {Engine#analyze_column_values} makes them
    def initialize(mapped_columns:)
      @mapped_columns = mapped_columns
    end

    # @param row [Hash{String => String, nil}] a row as the reader yields it
    # @return [Hash{String => Object}] target column => the value to load: the value mapping applied, and
    #   nil when the result is blank
    def result_of_row(row:)
      values = {}

      @mapped_columns.each do |target_column_name, mapped_column|
        value_mapping = mapped_column.fetch(:value_mapping, {})
        source_value = row[mapped_column[:source_column]]
        value = value_mapping.fetch(source_value, source_value)
        value = nil if Utilities.blank?(value: value)

        values[target_column_name] = value
      end

      values
    end
  end
end
