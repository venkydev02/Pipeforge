# frozen_string_literal: true

module Pipeforge
  # The base class of every error the engine raises on purpose.
  class Error < StandardError; end

  # Raised when the configuration file (engine.yml) cannot be used: it was not found, it is
  # not valid YAML, or it contains a section or setting the engine does not know.
  class ConfigurationError < Error; end

  # The errors about the source file: the file itself, its header and its rows.
  module Source
    # Raised when the source path is not a file the engine can read (it does not exist, it
    # is a directory, or access is denied).
    class MissingSourceError < Pipeforge::Error; end

    # Raised by the header stage when the source file has no content at all, so there is no
    # header to read. A file with a header and no data rows is not an error.
    class EmptySourceError < Pipeforge::Error; end

    # Raised when a mapped source column is not in the header of the file. Columns that are
    # not mapped are never checked.
    class MissingColumnError < Pipeforge::Error; end

    # Raised when a row cannot be parsed (for example a quote that is never closed).
    class MalformedSourceError < Pipeforge::Error
      # @return [Integer] the physical line of the file where the problem starts
      attr_reader :line

      # @param message [String] what is wrong
      # @param line [Integer] the physical line where the problem starts
      def initialize(message:, line:)
        super(message)
        @line = line
      end
    end
  end
end
