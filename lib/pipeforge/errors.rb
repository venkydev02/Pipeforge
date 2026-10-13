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
  #     Pipeforge::Configuration.new(path: "config/engine.yml")
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
      new(message: message, errors: [{code: code, message: message, **context}])
    end

    # @param message [String] the sentence for a person, for the whole error
    # @param errors [Array<Hash>] one entry per mistake, each with +code+ and +message+
    def initialize(message:, errors:)
      super(message)
      @errors = errors
    end

    # @return [Array<Symbol>] the code of each entry, in order
    def codes
      errors.map { |entry| entry[:code] }
    end
  end

  # Raised when the configuration file (engine.yml) cannot be used. Each code is a subject and
  # what is wrong with it: +config_file_not_found+, +config_file_not_valid_yaml+,
  # +config_file_not_name_value_entries+, +engine_not_sections+, +unknown_section+,
  # +section_not_settings+, +unknown_setting+, +setting_not_positive_whole_number+,
  # +setting_not_encoding_name+.
  class ConfigurationError < Error; end

  # Raised when the mapped columns given to the value analyzer are missing information a
  # column needs. Codes: +column_missing_target_column+ and +column_missing_type+, one entry
  # for each missing piece.
  class IncompleteColumnsError < Error; end

  # The errors about the source file: the file itself, its header and its rows.
  module Source
    # Raised when the source path is not a file the engine can read (it does not exist, it
    # is a directory, or access is denied). Code: +source_not_readable+.
    class MissingSourceError < Pipeforge::Error; end

    # Raised by the header stage when the source file has no content at all, so there is no
    # header to read. A file with a header and no data rows is not an error. Code:
    # +source_empty+.
    class EmptySourceError < Pipeforge::Error; end

    # Raised when a mapped source column is not in the header of the file. Columns that are
    # not mapped are never checked. Code: +mapped_column_not_in_file+, one entry for each column.
    class MissingColumnError < Pipeforge::Error; end

    # Raised when a row cannot be parsed (for example a quote that is never closed). Code:
    # +malformed_row+.
    class MalformedSourceError < Pipeforge::Error
      # @return [Integer] the physical line of the file where the error starts
      attr_reader :line

      # @param message [String] what is wrong
      # @param line [Integer] the physical line where the error starts
      def initialize(message:, line:)
        super(message: message, errors: [{code: :malformed_row, message: message, line: line}])
        @line = line
      end
    end
  end
end
