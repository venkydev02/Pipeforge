# frozen_string_literal: true

module Pipeforge
  # The outcome of one chunk of rows, as the run hands it to the consumer.
  #   first_row_number, last_row_number  absolute 1-based data record numbers of the first and the last
  #                                      row of the chunk (the header is not counted)
  #   processed_rows_count               rows in the chunk
  #   valid_rows_count                   rows that passed the validation
  #   failed_rows_count                  rows that did not
  #   failed_rows                        a {FailedRow} for each failed row, in file order
  ChunkResult = Data.define(
    :first_row_number, :last_row_number, :processed_rows_count, :valid_rows_count, :failed_rows_count,
    :failed_rows
  )

  # Checks one chunk of rows: each row becomes a {RowCandidate}, and each row that is not valid becomes
  # a {FailedRow}.
  module ChunkProcessor
    class << self
      # Checks one chunk of rows.
      #
      # @param rows [Array<Hash{String => String, nil}>] one chunk, as the reader yields it
      # @param first_row_number [Integer] absolute 1-based data record number of the first row
      # @param transformer [RowTransformer]
      # @param schema_checker [SchemaChecker]
      # @param target_schema [TargetSchema]
      # @param model_adapter [#build_record, #preload_parents] the adapter's object for the target table
      # @return [ChunkResult]
      def call(rows:, first_row_number:, transformer:, schema_checker:, target_schema:, model_adapter:)
        candidates = build_candidates(
          rows: rows, first_row_number: first_row_number, transformer: transformer,
          target_schema: target_schema, model_adapter: model_adapter
        )

        model_records = []
        candidates.each { |candidate| model_records << candidate.model_record }
        # One query for each association for the whole chunk, so the model's validation does not query the
        # parent of each row.
        model_adapter.preload_parents(records: model_records)

        failed_rows = validate_candidates(candidates: candidates, schema_checker: schema_checker)

        ChunkResult.new(
          first_row_number: first_row_number,
          last_row_number: first_row_number + rows.size - 1,
          processed_rows_count: rows.size,
          valid_rows_count: rows.size - failed_rows.size,
          failed_rows_count: failed_rows.size,
          failed_rows: failed_rows
        )
      end

      private

      def build_candidates(rows:, first_row_number:, transformer:, target_schema:, model_adapter:)
        candidates = []

        rows.each_with_index do |row, position|
          mapped_values = transformer.result_of_row(row: row)

          candidates << RowCandidate.new(
            row_number: first_row_number + position,
            mapped_values: mapped_values,
            record_attributes: record_attributes_without_empty_defaults(
              mapped_values: mapped_values, target_schema: target_schema
            ),
            model_adapter: model_adapter
          )
        end

        candidates
      end

      # The attributes a record is built from: the mapped values without the empty ones on a column that
      # has a default.
      def record_attributes_without_empty_defaults(mapped_values:, target_schema:)
        record_attributes = mapped_values.dup

        target_schema.columns.each do |target_column|
          next unless record_attributes[target_column.name].nil?
          # Left out so the column's default fills it; a column with no default keeps the empty value.
          next if target_column.default.nil?

          record_attributes.delete(target_column.name)
        end

        record_attributes
      end

      # Checks every candidate and returns the failed rows of the ones that are not valid, in file order.
      def validate_candidates(candidates:, schema_checker:)
        failed_rows = []

        candidates.each do |candidate|
          unless candidate.valid?(schema_checker: schema_checker)
            failed_rows << candidate.failed_row
          end
        end

        failed_rows
      end
    end
  end
end
