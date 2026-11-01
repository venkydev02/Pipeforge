# frozen_string_literal: true

require_relative "row_transformer"
require_relative "schema_checker"
require_relative "row_candidate"
require_relative "chunk_processor"

module Pipeforge
  # The totals of a run, over every chunk.
  #   processed_rows_count  rows read
  #   valid_rows_count      rows that passed the validation
  #   failed_rows_count     rows that did not
  RunResult = Data.define(:processed_rows_count, :valid_rows_count, :failed_rows_count)

  # Runs the validation layer of a migration over the whole source: it reads the rows in chunks, gives
  # each chunk to {ChunkProcessor}, and adds up the counts.
  module Runtime
    class << self
      # Checks every row of the source and yields each chunk's result to the block as the chunk is done.
      #
      # @param source_reader [Source::CsvReader] the reader of the source
      # @param mapped_columns [Hash{String => Hash}] target column => {source_column:, value_mapping:}
      # @param target_schema [TargetSchema]
      # @param offset [Integer] rows to skip before the first one processed
      # @param limit [Integer, nil] the most rows to process after the offset; nil processes them all
      # @param mode [Symbol] +:dry_run+ or +:run+
      # @param model_adapter [#build_record, #preload_parents] the adapter's object for the target table
      #   (see {TargetAdapter.model_adapter})
      # @yieldparam chunk_result [ChunkResult] the outcome of one chunk
      # @return [RunResult]
      def call(source_reader:, mapped_columns:, target_schema:, offset:, limit:, mode:, model_adapter:)
        transformer = RowTransformer.new(mapped_columns: mapped_columns)
        schema_checker = SchemaChecker.new(target_schema: target_schema)
        processed_rows_count = 0
        valid_rows_count = 0
        failed_rows_count = 0
        first_row_number = offset + 1

        # The reader gives only the columns the mapping uses, so a chunk holds no unused cells.
        source_reader.each_chunk(
          offset: offset, limit: limit, columns: source_columns_of(mapped_columns: mapped_columns)
        ) do |rows|
          chunk_result = ChunkProcessor.call(
            rows: rows, first_row_number: first_row_number, transformer: transformer,
            schema_checker: schema_checker, target_schema: target_schema, model_adapter: model_adapter
          )
          yield chunk_result if block_given?

          processed_rows_count += chunk_result.processed_rows_count
          valid_rows_count += chunk_result.valid_rows_count
          failed_rows_count += chunk_result.failed_rows_count
          first_row_number = chunk_result.last_row_number + 1
        end

        RunResult.new(
          processed_rows_count: processed_rows_count,
          valid_rows_count: valid_rows_count,
          failed_rows_count: failed_rows_count
        )
      end

      private

      # The source columns that the mapped columns read, each once.
      def source_columns_of(mapped_columns:)
        source_columns = []

        mapped_columns.each_value do |mapped_column|
          source_column = mapped_column[:source_column]
          source_columns << source_column unless source_columns.include?(source_column)
        end

        source_columns
      end
    end
  end
end
