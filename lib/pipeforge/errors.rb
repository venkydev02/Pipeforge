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
  # {MappedDataValidator}). Codes: +mapped_columns_not_name_value_entries+ (the mapped columns
  # are not a Hash; raised alone), +mapped_column_not_name_value_entries+ (an entry is not a
  # Hash), +target_column_not_in_schema+ (the target column is not a column of the table that can
  # be loaded), +column_missing_source_column+, +mapped_column_not_in_file+,
  # +value_mapping_not_name_value_entries+ (the value mapping is not a Hash) and
  # +required_column_unmapped+ (a required target column has no entry), one entry for each
  # mistake.
  class InvalidMappedColumnsError < Error; end

  # Raised by a target that cannot read the schema of the target. A table that does
  # not exist is the shared code +target_table_not_found+ (field +table_name+). A code that belongs
  # to one adapter carries its name, for example +active_record_model_not_found+ (field +model_name+).
  class TargetSchemaError < Error; end

  # The errors about the source file: the file itself, its header and its rows.
  module Source
    # Raised when the source file cannot be used. One entry for each mistake, told apart by its code:
    # +source_empty+ (no header line to read; a file with a header and no data rows is not an error),
    # +source_header_blank+ (a header cell is blank, with its +position+), +source_header_duplicated+ (a name
    # appears twice, with the +source_column_name+), +malformed_row+ (a row cannot be parsed, for example a quote
    # that is never closed) and +source_row_too_long+ (a row has more cells than the header). The two row codes
    # have the +line+ where the row starts.
    class Error < Pipeforge::Error; end
  end
end
