# frozen_string_literal: true

require_relative "run_processor/row_transformer"
require_relative "run_processor/schema_checker"
require_relative "run_processor/chunk_processor"

module Pipeforge
  # Runs a migration over the whole source: it reads the rows in chunks, gives each chunk to
  # {ChunkProcessor}, which validates and writes the rows, and adds up the counts.
  module RunProcessor
    # The totals of a run, over every chunk.
    #   processed_rows_count  rows read
    #   valid_rows_count      rows that passed the validation and were written
    #   failed_rows_count     rows that did not
    RunResult = Data.define(:processed_rows_count, :valid_rows_count, :failed_rows_count)

    class << self
      # Writes every row of the source and yields each chunk's result to the block as the chunk is done.
      #
      # A +:run+ writes each row in its own transaction and keeps it. A +:dry_run+ writes the same rows inside
      # one transaction that is rolled back when the last chunk is done, so nothing is kept; the block is
      # called inside that transaction, so it must not write to the target database.
      #
      # @param source_reader [Source::CsvReader] the reader of the source
      # @param resolved_mapped_columns [Hash{String => ResolvedMappedColumn}] target column name => its source column,
      #   value mapping and target column; only these columns are read and checked
      # @param offset [Integer] rows to skip before the first one processed
      # @param chunk_size [Integer] rows read, processed and yielded at a time
      # @param mode [Symbol] +:dry_run+ or +:run+
      # @param target [#build_record, #preload_parents, #transaction] the target of the target model
      #   (see {Engine})
      # @yieldparam chunk_result [ChunkResult] the outcome of one chunk
      # @return [RunResult]
      def call(source_reader:, resolved_mapped_columns:, offset:, chunk_size:, mode:, target:, &on_chunk)
        if mode == :dry_run
          target.transaction(rollback_at_end: true) do
            read_and_process_chunks(
              source_reader: source_reader, resolved_mapped_columns: resolved_mapped_columns,
              offset: offset, chunk_size: chunk_size, target: target, &on_chunk
            )
          end
        else
          read_and_process_chunks(
            source_reader: source_reader, resolved_mapped_columns: resolved_mapped_columns,
            offset: offset, chunk_size: chunk_size, target: target, &on_chunk
          )
        end
      end

      private

      # Reads the source in chunks, gives each to {ChunkProcessor}, yields each result to the block and
      # adds up the counts.
      def read_and_process_chunks(source_reader:, resolved_mapped_columns:, offset:, chunk_size:, target:)
        transformer = RowTransformer.new(resolved_mapped_columns: resolved_mapped_columns)
        schema_checker = SchemaChecker.new(resolved_mapped_columns: resolved_mapped_columns)
        processed_rows_count = 0
        valid_rows_count = 0
        failed_rows_count = 0
        first_row_number = offset + 1

        # The reader gives only the columns the mapping uses, so a chunk holds no unused cells.
        source_reader.each_chunk(
          offset: offset, chunk_size: chunk_size,
          columns: source_column_names_of(resolved_mapped_columns: resolved_mapped_columns)
        ) do |rows|
          chunk_result = ChunkProcessor.call(
            rows: rows, first_row_number: first_row_number, transformer: transformer,
            schema_checker: schema_checker, resolved_mapped_columns: resolved_mapped_columns, target: target
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

      # The source columns that the mapped columns read, each once.
      def source_column_names_of(resolved_mapped_columns:)
        source_column_names = []

        resolved_mapped_columns.each_value do |resolved_mapped_column|
          source_column_name = resolved_mapped_column.source_column_name
          source_column_names << source_column_name unless source_column_names.include?(source_column_name)
        end

        source_column_names
      end
    end
  end
end
