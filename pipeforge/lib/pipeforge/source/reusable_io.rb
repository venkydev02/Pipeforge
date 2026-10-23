# frozen_string_literal: true

module Pipeforge
  module Source
    # The source of the engine: the IO the consumer gave, wrapped so it can be read again and
    # again. The engine builds one when it is created, and every part that reads the source
    # works with it.
    #
    # smarter_csv closes the file it reads when it finishes, so without this wrapper the
    # consumer's IO would be closed after the first pass and could not be read again. The wrapper
    # offers the methods smarter_csv reads with and no +close+.
    #
    # The IO must respond to +read+, +rewind+ and +seek+ (ADR-17 item 12); the wrapper checks
    # that when it is built.
    #
    # @example
    #   source_io = Pipeforge::Source::ReusableIO.new(io: File.open("data/users.csv"))
    #   source_io.identifier  # => "data/users.csv"
    class ReusableIO
      # The methods the IO must have, and the error code for each one that is missing.
      REQUIRED_METHODS = {
        read: :source_io_missing_read,
        rewind: :source_io_missing_rewind,
        seek: :source_io_missing_seek
      }.freeze

      # @param io [IO] the source to read through, for example +File.open("data/users.csv")+
      # @raise [UnsupportedSourceError] the IO lacks a method the engine needs; every missing
      #   method is listed
      def initialize(io:)
        reject_missing_methods(io: io)
        @io = io
      end

      # smarter_csv calls this with the record separator as its only argument, so the signature
      # is fixed by the gem.
      def gets(*args)
        @io.gets(*args)
      end

      def read(*args)
        @io.read(*args)
      end

      def rewind
        @io.rewind
      end

      # smarter_csv reads text in this encoding when the IO reports one.
      def external_encoding
        @io.external_encoding
      end

      def eof?
        @io.eof?
      end

      # @return [String] the file path of the IO when it has one, else the name of its class
      def identifier
        return @io.path.to_s if @io.respond_to?(:path)

        @io.class.name
      end

      private

      # Raises UnsupportedSourceError, listing every method the IO does not have.
      def reject_missing_methods(io:)
        errors = []

        REQUIRED_METHODS.each do |method_name, code|
          next if io.respond_to?(method_name)

          errors << {
            code: code,
            message: "source does not respond to #{method_name}",
            method: method_name
          }
        end

        return if errors.empty?

        raise UnsupportedSourceError.new(errors: errors)
      end
    end
  end
end
