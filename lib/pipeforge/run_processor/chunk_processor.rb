# frozen_string_literal: true

module Pipeforge
  module RunProcessor
    # The outcome of one chunk of rows, as the run hands it to the consumer.
    #   first_row_number, last_row_number  absolute 1-based data record numbers of the first and the last
    #                                      row of the chunk (the header is not counted)
    #   processed_rows_count               rows in the chunk
    #   valid_rows_count                   rows that passed the validation and were written
    #   failed_rows_count                  rows that did not
    #   failed_rows                        a {FailedRow} for each failed row, in file order
    ChunkResult = Data.define(
      :first_row_number, :last_row_number, :processed_rows_count, :valid_rows_count, :failed_rows_count,
      :failed_rows
    )

    # One row that failed, as the consumer sees it.
    #   row_number  absolute 1-based data record number (the header is not counted)
    #   attributes  what the model record held when the row failed, as plain JSON types: column => value for the
    #               mapped columns, in the order of the mapping, cast to the type of the column and after the
    #               model's callbacks. It is never the raw source row.
    #   errors      one entry for each mistake: {origin:, target_column_name:, code:, message:}. +origin+ is where it
    #               was found: +:schema+ (the core's checks of the target schema), +:model+ (the application
    #               model's validations and callbacks) or +:database+ (the database refused the row).
    FailedRow = Data.define(:row_number, :attributes, :errors)

    # Processes one chunk of rows: each row gets a model record, which is validated on two levels, the
    # model's and the schema's, and, when valid, written before the next row is looked at. A row that is not
    # valid, or that the database refuses, becomes a {FailedRow}.
    module ChunkProcessor
      class << self
        # Validates and writes one chunk of rows.
        #
        # @param rows [Array<Hash{String => String, nil}>] one chunk, as the reader yields it
        # @param first_row_number [Integer] absolute 1-based data record number of the first row
        # @param transformer [RowTransformer]
        # @param schema_checker [SchemaChecker]
        # @param resolved_mapped_columns [Hash{String => ResolvedMappedColumn}] target column name => its resolved
        #   mapped column; a failed row shows these columns
        # @param target [#build_record, #preload_parents] the target of the target model; the
        #   record it builds is written with +load+
        # @return [ChunkResult]
        def call(rows:, first_row_number:, transformer:, schema_checker:, resolved_mapped_columns:, target:)
          model_records = build_model_records(rows: rows, transformer: transformer, target: target)

          # One query for each association for the whole chunk, so the model's validation does not query the
          # parent of each row.
          target.preload_parents(records: model_records)

          failed_rows = validate_and_load(
            model_records: model_records, first_row_number: first_row_number, schema_checker: schema_checker,
            target_column_names: resolved_mapped_columns.keys
          )

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

        # The model record of each row, in file order.
        def build_model_records(rows:, transformer:, target:)
          model_records = []

          rows.each do |row|
            model_records << target.build_record(attributes: transformer.result_of_row(row: row))
          end

          model_records
        end

        # Takes the model records one at a time, in row order: validates a record and, when it has no error,
        # loads it before the next record is looked at. Returns the failed rows of the chunk.
        def validate_and_load(model_records:, first_row_number:, schema_checker:, target_column_names:)
          failed_rows = []

          model_records.each_with_index do |model_record, position|
            add_errors(model_record: model_record, schema_checker: schema_checker)

            # One row at a time: a later row is validated after the earlier ones are in the table, so the
            # model's own uniqueness check also finds two rows of the file with the same value.
            next if model_record.errors.empty? && model_record.load

            # The record also holds columns the consumer did not map (the primary key, a generated column), so only
            # the mapped columns are shown. After a refused write the record's errors are the database's.
            failed_rows << FailedRow.new(
              row_number: first_row_number + position,
              attributes: model_record.json_attributes.slice(*target_column_names),
              errors: model_record.errors.values
            )
          end

          failed_rows
        end

        # Adds the errors of the two levels to the record, one for each column: the record keeps the first error
        # of a column, so the ones it found itself come before the schema's.
        def add_errors(model_record:, schema_checker:)
          model_record.valid?

          # The schema is checked on what the model record holds after its validation, because the model's
          # callbacks can change a value.
          schema_checker.call(attributes: model_record.attributes).each do |entry|
            model_record.add_error(**entry)
          end
        end
      end
    end
  end
end
