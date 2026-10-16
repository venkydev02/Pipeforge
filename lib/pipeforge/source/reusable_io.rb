# frozen_string_literal: true

module Pipeforge
  module Source
    # Lets smarter_csv read an IO without closing it. smarter_csv closes the file it reads when
    # it finishes, so without this wrapper the caller's IO would be closed after the first pass
    # and could not be read again. The wrapper offers only the methods smarter_csv reads with,
    # and no +close+.
    class ReusableIO
      # @param io [IO] the source to read through
      def initialize(io:)
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

      # smarter_csv reads text in this encoding when the IO reports one.
      def external_encoding
        @io.external_encoding
      end

      def eof?
        @io.eof?
      end
    end
  end
end
