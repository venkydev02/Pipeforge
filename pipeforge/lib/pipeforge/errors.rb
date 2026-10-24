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
  #     Pipeforge::Configuration.load
  #   rescue Pipeforge::ConfigurationError => error
  #     error.codes  # => [:unknown_section, :setting_not_positive_whole_number]
  #     error.errors # => [{code: :unknown_section, message: "unknown section loging", section: "loging"}, ...]
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

  # Raised when the configuration file (config/pipeforge.yml) cannot be used. A missing file is
  # not an error: every setting then has its default. Each code is a subject and what is wrong
  # with it: +config_file_not_valid_yaml+, +config_file_not_name_value_entries+,
  # +engine_not_sections+, +unknown_section+, +section_not_settings+, +unknown_setting+,
  # +setting_not_positive_whole_number+, +setting_not_whole_number_0_to_100+ and
  # +setting_not_true_or_false+.
  class ConfigurationError < Error; end

  # Raised when the mapped columns given to {Engine#analyze_values} cannot be used (checked by
  # {MappedDataValidator}). Codes: +mapped_columns_not_name_value_entries+ (the mapped columns
  # are not a Hash; raised alone), +mapped_column_not_name_value_entries+ (an entry is not a
  # Hash), +target_column_not_in_schema+ (the target column is not a column of the table that can
  # be loaded), +column_missing_source_column+, +mapped_column_not_in_file+,
  # +value_mapping_not_name_value_entries+ (the value mapping is not a Hash) and
  # +required_column_unmapped+ (a required target column has no entry), one entry for each
  # mistake.
  class InvalidMappedColumnsError < Error; end

  # Raised when the engine needs a target adapter and none is installed
  # (+target_adapter_not_installed+).
  class TargetAdapterError < Error; end

  # Raised by a target adapter that cannot read the schema of the target. A table that does
  # not exist is the shared code +target_table_not_found+ (field +table+). A code that belongs
  # to one adapter carries its name, for example +active_record_model_not_found+.
  class TargetSchemaError < Error; end

  # The errors about the source file: the file itself, its header and its rows.
  module Source
    # Raised when the source object lacks a method the engine needs (+read+, +rewind+ or +seek+).
    # Codes: +source_io_missing_read+, +source_io_missing_rewind+, +source_io_missing_seek+, one
    # entry for each missing method.
    class UnsupportedSourceError < Pipeforge::Error; end

    # Raised by the header stage when the source file has no content at all, so there is no
    # header to read. A file with a header and no data rows is not an error. Code:
    # +source_empty+.
    class EmptySourceError < Pipeforge::Error; end

    # Raised by the header stage when the header row cannot be used: a header cell is blank
    # (+source_header_blank+, with its +position+) or a name appears twice
    # (+source_header_duplicated+, with the +source_column+). One entry for each mistake.
    class InvalidHeaderError < Pipeforge::Error; end

    # Raised when a row cannot be used as written: it cannot be parsed (for example a quote that
    # is never closed, code +malformed_row+) or it has more cells than the header (code
    # +source_row_too_long+).
    class MalformedSourceError < Pipeforge::Error
      # @return [Integer] the physical line of the file where the error starts
      attr_reader :line

      # @param message [String] what is wrong
      # @param line [Integer] the physical line where the error starts
      # @param code [Symbol] +:malformed_row+ or +:source_row_too_long+
      def initialize(message:, line:, code: :malformed_row)
        super(errors: [{code: code, message: message, line: line}])
        @line = line
      end
    end
  end
end
