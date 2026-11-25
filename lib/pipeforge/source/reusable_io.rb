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
    # The IO must respond to +read+, +rewind+ and +seek+; the wrapper checks that when it is
    # built.
    #
    # @example
    #   source_io = Pipeforge::Source::ReusableIO.new(io: File.open("data/users.csv"))
    class ReusableIO
      # The methods the IO must have.
      REQUIRED_METHODS = %i[read rewind seek].freeze

      # @param io [IO] the source to read through, for example +File.open("data/users.csv")+
      # @raise [ArgumentError] the IO lacks a method the engine needs; every missing method is named in
      #   the message
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

      private

      # Raises ArgumentError, naming every method the IO does not have.
      def reject_missing_methods(io:)
        missing_method_names = []

        REQUIRED_METHODS.each do |method_name|
          missing_method_names << method_name unless io.respond_to?(method_name)
        end

        return if missing_method_names.empty?

        raise ArgumentError, ArgumentMessages::MESSAGES.fetch(:source_missing_methods).call(
          required_method_names: REQUIRED_METHODS, missing_method_names: missing_method_names
        )
      end
    end
  end
end
