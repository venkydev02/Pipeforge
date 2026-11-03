# frozen_string_literal: true

require_relative "column_limits_checker"

module Pipeforge
  # The checks the core can make on one record from the target schema alone, without reading any row:
  #   - a required column left empty:                    +value_missing+
  #   - a value outside the limits of its column, as {ColumnLimitsChecker} finds it:
  #       a string or text longer than +max_length+:     +value_too_long+
  #       an integer outside the size from +limit+
  #       (from 0 for an unsigned column), a decimal with
  #       more digits before the point than +precision -
  #       scale+ once rounded to the scale, or a float
  #       that is infinite or larger than the column
  #       holds:                                         +value_out_of_range+
  #       a value that is not a label or stored value
  #       of an enum column:                             +value_not_allowed+
  # Whether a value fits the type of its column is not checked: a value that does not look like the
  # type (+abc+ in an integer column) is left to the cast of the framework.
  #
  # A value may be text or already cast to the type of its column (an Integer, a Float or a decimal number).
  class SchemaChecker
    # @param target_schema [TargetSchema]
    def initialize(target_schema:)
      @target_columns = target_schema.columns
      @limits_by_column = {}

      @target_columns.each do |target_column|
        @limits_by_column[target_column.name] = ColumnLimitsChecker.new(type_info: target_column.to_h)
      end
    end

    # @param attributes [Hash{String => Object}] target column => value to load
    # @return [Array<Hash>] one entry {origin: :schema, code:, message:, target_column:} for each mistake;
    #   empty when the record passes
    def call(attributes:)
      errors = []

      @target_columns.each do |target_column|
        value = attributes[target_column.name]

        if value.nil?
          errors << missing_error(target_column: target_column) if target_column.required
          next
        end

        violation = @limits_by_column.fetch(target_column.name).violation_of(value: value)
        errors << limit_error(target_column: target_column, violation: violation) unless violation.nil?
      end

      errors
    end

    private

    def missing_error(target_column:)
      {
        origin: :schema,
        code: :value_missing,
        message: "#{target_column.name} is required but its value is empty",
        target_column: target_column.name
      }
    end

    def limit_error(target_column:, violation:)
      {
        origin: :schema,
        code: violation.code,
        message: "#{target_column.name}: #{violation.detail}",
        target_column: target_column.name
      }
    end
  end
end
