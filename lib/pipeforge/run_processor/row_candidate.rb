# frozen_string_literal: true

module Pipeforge
  module RunProcessor
    # One row that failed, as the consumer sees it.
    #   row_number  absolute 1-based data record number (the header is not counted)
    #   mapped_values  the row after the column mapping and the value mapping, keyed by target column. It is
    #                  never the raw source row.
    #   errors      one entry for each mistake: {origin:, target_column:, code:, message:}. +origin+ is where it
    #               was found: +:schema+ (the core's checks of the target schema), +:model+ (the application
    #               model's validations and callbacks) or +:database+ (the database refused the row).
    FailedRow = Data.define(:row_number, :mapped_values, :errors)

    # One record on its way through the run, built from the transformed values of a row. {#valid?} checks
    # it and {#load} writes it; both keep the errors they find. It is mutable: {#valid?} replaces its
    # errors each time it runs, and a refused {#load} replaces them with the database's.
    class RowCandidate
      # @return [Integer] absolute 1-based data record number (the header is not counted)
      attr_reader :row_number

      # @return [Hash{String => Object}] the row after the column mapping and the value mapping, keyed by
      #   target column, as {RowTransformer} gave it
      attr_reader :mapped_values

      # @return [Hash{String => Object}] the attributes the model record was built from
      attr_reader :record_attributes

      # @return [#valid?, #load, #errors, #attributes] the adapter's wrapper of one record, built from the
      #   attributes. +load+ writes it and is true when the target took it; +valid?+ runs the model's
      #   checks and is true when it finds no mistake; +errors+ is one
      #   entry {origin:, code:, message:, target_column:} for each mistake the last +valid?+ or +load+ found;
      #   +attributes+ is
      #   column => the value the record holds now, cast to the column's type and after the model's callbacks.
      attr_reader :model_record

      # @return [Array<Hash>] one entry {origin:, code:, message:, target_column:} for each mistake; empty until
      #   {#valid?}
      attr_reader :errors

      # Builds the model record from the record attributes.
      #
      # @param row_number [Integer]
      # @param mapped_values [Hash{String => Object}] the row after the column mapping and the value mapping,
      #   which the failed row shows
      # @param record_attributes [Hash{String => Object}] what the record is built from
      # @param model_adapter [#build_record] the adapter's object for the target table
      def initialize(row_number:, mapped_values:, record_attributes:, model_adapter:)
        @row_number = row_number
        @mapped_values = mapped_values
        @errors = []
        @record_attributes = record_attributes
        @model_record = model_adapter.build_record(attributes: record_attributes)
      end

      # Checks the built record on two levels, the model's and the schema's, and keeps one entry for each
      # mistake in {#errors}.
      #
      # @param schema_checker [SchemaChecker]
      # @return [Boolean] true when neither level found a mistake
      def valid?(schema_checker:)
        model_errors = []
        model_errors = @model_record.errors unless @model_record.valid?
        # The schema is checked on what the model record holds after its validation, because the model's
        # callbacks can change a value.
        schema_errors = schema_checker.call(attributes: @model_record.attributes)
        @errors = merge_errors(model_errors: model_errors, schema_errors: schema_errors)

        @errors.empty?
      end

      # Writes the row to the target; call it only after {#valid?} returned true. When the database
      # refuses the row, {#errors} holds the refusal's entries (with +origin: :database+, or +:model+ when a
      # callback of the model stopped the save).
      #
      # @return [Boolean] true when the row was written
      def load
        loaded = @model_record.load
        @errors = @model_record.errors unless loaded

        loaded
      end

      # The row as the consumer sees it when it did not pass: its transformed values and its errors, each
      # with the origin it came from.
      #
      # @return [FailedRow]
      def failed_row
        FailedRow.new(row_number: @row_number, mapped_values: @mapped_values, errors: @errors.dup)
      end

      private

      # Puts the errors of the two levels together so that a mistake is reported once: the same target
      # column with the same code appears once, and the model-level entry is the one kept.
      #
      # @param model_errors [Array<Hash>] entries {origin: :model, code:, message:, target_column:}
      # @param schema_errors [Array<Hash>] entries {origin: :schema, code:, message:, target_column:}
      # @return [Array<Hash>] the model-level entries, then the schema-level entries not already there
      def merge_errors(model_errors:, schema_errors:)
        merged = model_errors.dup

        schema_errors.each do |schema_error|
          already_there = merged.any? do |error|
            error[:target_column] == schema_error[:target_column] && error[:code] == schema_error[:code]
          end

          merged << schema_error unless already_there
        end

        merged
      end
    end
  end
end
