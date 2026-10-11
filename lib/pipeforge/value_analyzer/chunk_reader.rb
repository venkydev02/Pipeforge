# frozen_string_literal: true

require "smarter_csv"

module Pipeforge
  class ValueAnalyzer
    # Reads a CSV file in chunks of raw rows, using smarter_csv.
    #
    # Text is kept as written, with these exceptions: surrounding spaces and tabs are trimmed
    # from values and headers, and a cell that is empty or only whitespace arrives as nil. No
    # numbers are converted. Blank lines and rows whose cells are all empty are dropped before
    # they reach the caller.
    #
    # The reader does not validate the file or its columns; the header stage does that. A blank
    # header cell, or a row with more cells than the header, comes through under a made-up name
    # that no mapping can use.
    class ChunkReader
      EMPTY_VALUE = /\A[[:space:]]*\z/

      # Called by the gem for a row it cannot parse. Stops the scan with our own error and the
      # line where the row starts: an unclosed quote swallows every row after it, so skipping
      # the row would silently drop good rows.
      STOP_ON_BAD_ROW = lambda do |bad_row|
        line = bad_row[:file_line_number]
        raise Source::MalformedSourceError.new(
          message: "malformed CSV at line #{line}: #{bad_row[:error_message]}",
          line: line
        )
      end

      # +missing_header_prefix+ names a blank header cell, so that name can never be the gem's
      # default (column_1), which could be the name of a real, mapped column. Trimming is the
      # gem's default (+strip_whitespace: true+), so it is not listed.
      OPTIONS = {
        convert_values_to_numeric: false,
        remove_empty_values: false,
        nil_values_matching: EMPTY_VALUE,
        downcase_header: false,
        keep_original_headers: true,
        missing_header_prefix: "__unnamed_",
        on_bad_row: STOP_ON_BAD_ROW,
        verbose: :quiet
      }.freeze

      # @param path [String] path of a CSV file
      # @param config [Configuration] +execution.batch_size+ is the chunk size
      def initialize(path:, config:)
        @reader = SmarterCSV::Reader.new(path, OPTIONS.merge(chunk_size: config.execution.batch_size))
        @row_count = 0
      end

      # Yields each chunk of the file, in order.
      #
      # @yieldparam rows [Array<Hash{String => String, nil}>] header => raw text, or nil when empty
      # @return [Enumerator] when called without a block
      def each_chunk
        return enum_for(:each_chunk) unless block_given?

        @reader.each_chunk do |chunk, _index|
          @row_count += chunk.size
          yield chunk
        end
      end

      # The data rows handed out so far; complete once the whole file has been read. The gem's
      # own line counter also counts the header and the dropped rows, so it is not used.
      #
      # @return [Integer]
      attr_reader :row_count

      # The column names in file order, trimmed. Available once the file has been read, also
      # when it has no data rows.
      #
      # @return [Array<String>]
      def headers
        @reader.headers
      end
    end
  end
end
