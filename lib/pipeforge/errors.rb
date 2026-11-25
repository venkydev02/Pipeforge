# frozen_string_literal: true

module Pipeforge
  # The base class of every error the engine raises on purpose.
  #
  # An error holds +errors+: a list with one entry per mistake. Each entry has a stable +code+
  # (a Symbol that a program can check), a +message+ (the sentence for a person, which may be
  # reworded) and the fields that say where the mistake is (a setting, a column, a line).
  # Several mistakes found in one pass are raised together as one error.
  #
  # @example
  #   begin
  #     engine.analyze_column_values(mapped_columns: mapped_columns)
  #   rescue Pipeforge::InvalidMappedColumnsError => error
  #     error.codes  # => [:mapped_column_not_in_file, :required_column_unmapped]
  #     error.errors # => [{code: :mapped_column_not_in_file, message: "...", target_column_name: "email", source_column_name: "Mail"}, ...]
  #   end
  class Error < StandardError
    # @return [Array<Hash>] one entry per mistake: +code+, +message+ and the fields that locate it
    attr_reader :errors

    # An error for one mistake.
    #
    # @param code [Symbol] the stable name of the mistake
    # @param message [String] the sentence for a person
    # @param context [Hash] the fields that say where the mistake is
    # @return [Error]
    def self.single(code:, message:, **context)
      new(errors: [{code: code, message: message, **context}])
    end

    # The message of the whole error is the messages of its entries, joined with "; ", so it can
    # never differ from them. Give +message+ only when the whole error needs its own layout.
    #
    # @param errors [Array<Hash>] one entry per mistake, each with +code+ and +message+
    # @param message [String, nil] the sentence for the whole error, instead of the joined entries
    def initialize(errors:, message: nil)
      if message.nil?
        message = errors.map { |entry| entry[:message] }.join("; ")
      end

      super(message)
      @errors = errors
    end

    # @return [Array<Symbol>] the code of each entry, in order
    def codes
      errors.map { |entry| entry[:code] }
    end
  end

  # Raised when the mapped columns given to {Engine#analyze_column_values} cannot be used (checked by
  # {MappedColumns}) because they do not fit the table or the file. Codes:
  # +target_column_not_in_schema+ (the target column is not a column of the table that can be loaded),
  # +column_missing_source_column+, +mapped_column_not_in_file+ and +required_column_unmapped+ (a required target
  # column has no entry), one entry for each mistake. A mapping with the wrong shape is an ArgumentError instead.
  class InvalidMappedColumnsError < Error
    # The entries of the error, each written once and keyed by its code. The value of a key is a function that takes the
    # facts its sentence uses and returns the entry: the +code+, the +message+ (with the column first) and the fields
    # that locate the mistake.
    ENTRIES = {
      target_column_not_in_schema: ->(target_column_name:) {
        {
          code: :target_column_not_in_schema,
          message: "#{target_column_name} is not a column of the target table that can be loaded",
          target_column_name: target_column_name
        }
      },
      column_missing_source_column: ->(target_column_name:) {
        {
          code: :column_missing_source_column,
          message: "#{target_column_name} has no source_column_name",
          target_column_name: target_column_name
        }
      },
      mapped_column_not_in_file: ->(target_column_name:, source_column_name:) {
        {
          code: :mapped_column_not_in_file,
          message: "#{target_column_name} is mapped to the source column #{source_column_name}, which is not in the file",
          target_column_name: target_column_name,
          source_column_name: source_column_name
        }
      },
      required_column_unmapped: ->(target_column_name:) {
        {
          code: :required_column_unmapped,
          message: "#{target_column_name} is required but no source column is mapped to it",
          target_column_name: target_column_name
        }
      }
    }.freeze
  end

  # Raised by a target that cannot read the schema of the target. A table that does
  # not exist is the shared code +target_table_not_found+ (field +table_name+). A code that belongs
  # to one adapter carries its name, for example +active_record_model_not_found+ (field +model_name+).
  class TargetSchemaError < Error
    # The entries of the error, each written once and keyed by its code. The value of a key is a function that takes the
    # facts its sentence uses and returns the entry: the +code+, the +message+ and the fields that locate the mistake.
    ENTRIES = {
      active_record_model_not_found: ->(target_model_name:) {
        {
          code: :active_record_model_not_found,
          message: "no loaded model is named #{target_model_name}; the model must be loaded before the schema is read",
          model_name: target_model_name
        }
      },
      target_table_not_found: ->(table_name:, model_name:) {
        {
          code: :target_table_not_found,
          message: "table #{table_name} of #{model_name} does not exist in the database",
          table_name: table_name
        }
      }
    }.freeze
  end

  # The errors about the source file: the file itself, its header and its rows.
  module Source
    # Raised when the source file cannot be used. One entry for each mistake, told apart by its code:
    # +source_empty+ (no header line to read; a file with a header and no data rows is not an error),
    # +source_header_blank+ (a header cell is blank, with its +position+), +source_header_duplicated+ (a name
    # appears twice, with the +source_column_name+), +malformed_row+ (a row cannot be parsed, for example a quote
    # that is never closed) and +source_row_too_long+ (a row has more cells than the header). The two row codes
    # have the +line+ where the row starts.
    class Error < Pipeforge::Error
      # The entries of the error, each written once and keyed by its code. The value of a key is a function that takes
      # the facts its sentence uses and returns the entry: the +code+, the +message+ and the fields that locate the
      # mistake.
      ENTRIES = {
        source_empty: -> {
          {code: :source_empty, message: "the source has no header row to read"}
        },
        source_header_blank: ->(position:) {
          {code: :source_header_blank, message: "header cell #{position} is blank", position: position}
        },
        source_header_duplicated: ->(source_column_name:, count:) {
          {
            code: :source_header_duplicated,
            message: "column name #{source_column_name} appears #{count} times",
            source_column_name: source_column_name
          }
        },
        malformed_row: ->(line:, reason:) {
          {code: :malformed_row, message: "malformed CSV at line #{line}: #{reason}", line: line}
        },
        source_row_too_long: ->(line:) {
          {
            code: :source_row_too_long,
            message: "the row at line #{line} has more cells than the header",
            line: line
          }
        }
      }.freeze
    end
  end
end
