# frozen_string_literal: true

module Pipeforge
  module RunProcessor
    # Applies the consumer's column mapping to one source row. It does the header mapping (which source
    # column feeds each target column) and the value mapping, and nothing else. A blank result is not a
    # value: the column is left out, so the target decides what an empty cell becomes.
    class RowTransformer
      # @param resolved_mapped_columns [Hash{String => ResolvedMappedColumn}] target column name => its resolved
      #   mapped column, whose value mapping has text keys
      def initialize(resolved_mapped_columns:)
        @resolved_mapped_columns = resolved_mapped_columns
      end

      # @param row [Hash{String => String, nil}] a row as the reader yields it
      # @return [Hash{String => Object}] target column => the value to load: the value mapping applied. A
      #   column whose result is blank is not in the Hash
      def result_of_row(row:)
        values = {}

        @resolved_mapped_columns.each do |target_column_name, resolved_mapped_column|
          source_value = row[resolved_mapped_column.source_column_name]
          value = resolved_mapped_column.value_mapping.fetch(source_value, source_value)

          # Left out so the column's default fills it; a column with no default is empty without it.
          next if Utilities.blank?(value: value)

          values[target_column_name] = value
        end

        values
      end
    end
  end
end
