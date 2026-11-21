# frozen_string_literal: true

require_relative "../column_limits_checker"

module Pipeforge
  module RunProcessor
    # The checks the core can make on one record from the columns the consumer mapped, without reading any row.
    # A column of the table that no entry fills is not checked: the model and the database check it.
    #   - a required column left empty:                    +value_missing+
    #   - a value outside the limits of its column, as {ColumnLimitsChecker} finds it:
    #       a string or text longer than +max_length+:     +value_too_long+
    #       an integer outside the size from +limit+
    #       (from 0 for an unsigned column), a decimal with
    #       more digits before the point than +precision -
    #       scale+ once rounded to the scale, or a float
    #       that is infinite or larger than the column
    #       holds:                                         +value_out_of_range+
    #       a value that is not a label
    #       of an enum column:                             +value_not_allowed+
    # Whether a value fits the type of its column is not checked: a value that does not look like the
    # type (+abc+ in an integer column) is left to the cast of the framework.
    #
    # A value may be text or already cast to the type of its column (an Integer, a Float or a decimal number).
    class SchemaChecker
      # @param resolved_mapped_columns [Hash{String => ResolvedMappedColumn}] target column name => its resolved
      #   mapped column; the checks are made on the target column of each
      def initialize(resolved_mapped_columns:)
        @target_columns = []
        resolved_mapped_columns.each_value { |resolved_mapped_column| @target_columns << resolved_mapped_column.target_column }

        @limits_by_column_name = {}

        @target_columns.each do |target_column|
          @limits_by_column_name[target_column.name] = ColumnLimitsChecker.for(target_column: target_column)
        end
      end

      # @param attributes [Hash{String => Object}] target column => value to load
      # @return [Array<ErrorCatalog::ColumnError>] one error for each mistake, as the {ErrorCatalog} builds it, with +origin: :schema+
      #   (its +value+ is the value that failed, nil for an empty required value); empty when the record passes
      def call(attributes:)
        errors = []

        @target_columns.each do |target_column|
          value = attributes[target_column.name]

          if value.nil?
            errors << missing_error(target_column: target_column) if target_column.required
            next
          end

          violation = @limits_by_column_name.fetch(target_column.name).violation_of(value: value)
          errors << violation unless violation.nil?
        end

        errors
      end

      private

      def missing_error(target_column:)
        ErrorCatalog::ERRORS.fetch(:value_missing).call(origin: :schema, target_column_name: target_column.name, value: nil)
      end
    end
  end
end
