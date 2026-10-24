# frozen_string_literal: true

require "smarter_csv"

module Pipeforge
  module Source
    # The CSV source reader. It reads a CSV file in chunks of raw rows, using smarter_csv, and
    # gives the core the source interface: +headers+ and +each_chunk+. The engine
    # builds one for its source, and every stage (header analysis, value analysis, run) reads the
    # file through it.
    #
    # The header is read once and kept. The rows are read again on every +each_chunk+ call.
    #
    # Text is kept as written, with these exceptions: surrounding spaces and tabs are trimmed
    # from values and headers, and a cell that is empty or only whitespace arrives as nil. No
    # numbers are converted. Blank lines and rows whose cells are all empty are dropped before
    # they reach the caller.
    #
    # The header is checked before any row is read (see +headers+), and a row with more cells
    # than the header stops the read (see +each_chunk+). A row with fewer cells is filled with nil.
    class CsvReader
      EMPTY_VALUE = /\A[[:space:]]*\z/

      # Called by the gem for a row it cannot use (an unclosed quote, or more cells than the
      # header). Stops the scan with a {MalformedSourceError} that carries the line where the row
      # starts.
      STOP_ON_BAD_ROW = lambda do |bad_row|
        line = bad_row[:file_line_number]

        if bad_row[:error_class] == SmarterCSV::HeaderSizeMismatch
          raise MalformedSourceError.new(
            message: "the row at line #{line} has more cells than the header",
            line: line,
            code: :source_row_too_long
          )
        end

        raise MalformedSourceError.new(
          message: "malformed CSV at line #{line}: #{bad_row[:error_message]}",
          line: line
        )
      end

      # The options every read passes to smarter_csv. Trimming is the gem's default.
      OPTIONS = {
        convert_values_to_numeric: false,
        remove_empty_values: false,
        nil_values_matching: EMPTY_VALUE,
        downcase_header: false,
        keep_original_headers: true,
        on_bad_row: STOP_ON_BAD_ROW,
        missing_headers: :raise,
        verbose: :quiet
      }.freeze

      # The options for reading only the header: one row at a time, and a repeated name is
      # reported by the gem instead of being renamed, so the names are read as written.
      HEADER_OPTIONS = OPTIONS.merge(
        chunk_size: 1,
        duplicate_header_suffix: nil,
        missing_headers: :auto
      ).freeze

      # @param source_io [ReusableIO] the CSV source; nothing is read until +headers+ or
      #   +each_chunk+ is called
      def initialize(source_io:)
        @source_io = source_io
      end

      # Yields each chunk of the file, in order. The header is checked first, so a file with an
      # unusable header yields nothing. The chunk size is the +execution.batch_size+ setting. Each
      # call reads the whole file again.
      #
      # A block is required: this method exists to go through the real file.
      #
      # @yieldparam rows [Array<Hash{String => String, nil}>] header => raw text, or nil when empty
      # @return [Integer] the number of data rows read, once the whole file has been read: blank
      #   lines and rows with only empty cells are not rows. The gem's own line counters also
      #   count the header and those dropped lines, so they are not used.
      # @raise [ArgumentError] no block is given
      # @raise [EmptySourceError] see +headers+
      # @raise [InvalidHeaderError] see +headers+
      # @raise [MalformedSourceError] a row cannot be parsed (+malformed_row+) or has more cells
      #   than the header (+source_row_too_long+)
      def each_chunk
        raise ArgumentError, "each_chunk needs a block" unless block_given?

        headers
        row_count = 0
        chunk_reader = SmarterCSV::Reader.new(@source_io, OPTIONS.merge(chunk_size: Configuration.execution.batch_size))

        chunk_reader.each_chunk do |chunk, _index|
          row_count += chunk.size
          yield chunk
        end

        row_count
      end

      # @return [String] the file path of the source when it has one, else the name of its class
      def identifier
        @source_io.identifier
      end

      # The column names in file order, trimmed. They are read from the first line of the file
      # without reading the rest of it (the first data row is parsed too, because the gem needs
      # it, so a malformed first row stops this as well), and then kept: later calls give the same
      # frozen list without reading the file.
      #
      # The header is checked: a name that appears twice and a blank cell are mistakes, and
      # every one is listed in one error.
      #
      # @return [Array<String>]
      # @raise [EmptySourceError] there is no header line to read (+source_empty+)
      # @raise [InvalidHeaderError] a header cell is blank or a name appears twice
      #   (+source_header_blank+, +source_header_duplicated+)
      def headers
        if @headers.nil?
          header_names = read_header_names
          reject_unusable_header(header_names: header_names)
          @headers = header_names.freeze
        end

        @headers
      end

      private

      # The real names, as written: a repeated name comes back repeated and a blank cell as "".
      # Empty when the file has no header line to read.
      def read_header_names
        header_reader = SmarterCSV::Reader.new(@source_io, HEADER_OPTIONS)
        read_first_chunk(header_reader: header_reader)

        header_reader.headers
      rescue SmarterCSV::EmptyFileError, SmarterCSV::NoColSepDetected
        []
      end

      # The gem reports a repeated name only after it has read the names, so the names are
      # kept and the report is ignored here; the check below decides what a repeat means.
      def read_first_chunk(header_reader:)
        header_reader.each_chunk { break }
      rescue SmarterCSV::DuplicateHeaders
        nil
      end

      # Raises when there is no header, or collects every blank cell and repeated name.
      def reject_unusable_header(header_names:)
        if header_names.empty?
          raise EmptySourceError.single(code: :source_empty, message: "the source has no header row to read")
        end

        errors = blank_cell_errors(header_names: header_names) + repeated_name_errors(header_names: header_names)
        return if errors.empty?

        raise InvalidHeaderError.new(errors: errors)
      end

      def blank_cell_errors(header_names:)
        errors = []

        header_names.each_with_index do |header_name, index|
          next unless header_name.empty?

          errors << {
            code: :source_header_blank,
            message: "header cell #{index + 1} is blank",
            position: index + 1
          }
        end

        errors
      end

      # One entry for each name that appears more than once. A blank cell is not a name.
      def repeated_name_errors(header_names:)
        counts = Hash.new(0)
        header_names.each { |header_name| counts[header_name] += 1 unless header_name.empty? }
        errors = []

        counts.each do |header_name, count|
          next if count == 1

          errors << {
            code: :source_header_duplicated,
            message: "column name #{header_name} appears #{count} times",
            source_column: header_name
          }
        end

        errors
      end
    end
  end
end
