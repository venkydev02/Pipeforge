# frozen_string_literal: true

require "date"

module Pipeforge
  module ValueAnalyzer
    # Decides whether a text value fits the type of the target column it is mapped to. The test
    # is strict: "abc" does not fit an integer.
    #
    # It reads only the text and the type information, never a table. A type with no rule
    # (json, inet, and so on) is not checked: every value fits it.
    #
    # An enum column accepts only its labels and the values stored for them, whatever its stored
    # type is.
    #
    # @example
    #   type_checker = TypeChecker.new(type_info: {type: "integer", limit: 4})
    #   type_checker.fits?(text: "42")   # => true
    #   type_checker.fits?(text: "42x")  # => false
    #
    # @example an enum column
    #   type_checker = TypeChecker.new(type_info: {type: "integer", enum_values: {"draft" => 0, "placed" => 1}})
    #   type_checker.fits?(text: "draft")  # => true
    #   type_checker.fits?(text: "1")      # => true
    #   type_checker.fits?(text: "7")      # => false
    class TypeChecker
      WHOLE_NUMBER = /\A[+-]?\d+\z/
      DECIMAL = /\A[+-]?\d+(\.\d+)?\z/
      FLOAT = /\A[+-]?\d+(\.\d+)?([eE][+-]?\d+)?\z/
      BOOLEAN_WORDS = %w[true false t f yes no y n 1 0].freeze
      DATE = /\A(\d{4})-(\d{2})-(\d{2})\z/
      TIME = /\A(\d{2}):(\d{2})(?::(\d{2})(?:\.\d{1,6})?)?\z/
      TIMESTAMP = /\A(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})(?::(\d{2})(?:\.\d{1,6})?)?(?:Z|[+-]\d{2}(?::?\d{2})?)?\z/
      UUID = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/

      # @param type_info [Hash] the type of the target column, from the target schema:
      #   +type+ (integer, float, decimal, string, text, boolean, date, time, timestamp, uuid),
      #   +limit+ (integer: size in bytes, 4 when not given), +max_length+ (string and text: the
      #   most characters allowed), +precision+ and +scale+ (decimal: the total digits and the
      #   digits after the point), and +enum_values+ (nil, or the label => stored value pairs of an
      #   enum column)
      # @raise [KeyError] when +type+ is missing
      def initialize(type_info:)
        @type = type_info.fetch(:type).to_s
        @enum_texts = enum_texts(enum_values: type_info[:enum_values])
        @max_length = type_info[:max_length]
        @precision = type_info[:precision]
        @scale = type_info[:scale] || 0
        set_integer_range(limit: type_info[:limit])
      end

      # @param text [String] a non-empty value; empty values are not checked
      # @return [Boolean] whether the text fits the type
      def fits?(text:)
        return @enum_texts.include?(text) unless @enum_texts.nil?

        case @type
        when "integer" then whole_number?(text: text)
        when "float" then float?(text: text)
        when "decimal" then decimal?(text: text)
        when "string", "text" then within_length?(text: text)
        when "boolean" then boolean?(text: text)
        when "date" then date?(text: text)
        when "time" then time?(text: text)
        when "timestamp", "datetime" then timestamp?(text: text)
        when "uuid" then uuid?(text: text)
        else true
        end
      end

      private

      # The texts an enum column accepts: its labels and the values stored for them. nil when the
      # column is not an enum.
      def enum_texts(enum_values:)
        return nil if enum_values.nil?

        enum_values.keys.map(&:to_s) + enum_values.values.map(&:to_s)
      end

      # Sets the smallest and largest whole number a column of +limit+ bytes holds (4 bytes when
      # no limit is given), which the whole number rule compares with.
      def set_integer_range(limit:)
        bits = 8 * (limit || 4)
        @largest = 2**(bits - 1) - 1
        @smallest = -(2**(bits - 1))
      end

      def whole_number?(text:)
        return false unless WHOLE_NUMBER.match?(text)

        text.to_i.between?(@smallest, @largest)
      end

      def float?(text:)
        FLOAT.match?(text)
      end

      # With a precision, the digits before the point must fit in precision - scale. Extra
      # digits after the point are only rounded by the database, so they are allowed.
      def decimal?(text:)
        return false unless DECIMAL.match?(text)
        return true if @precision.nil?

        digits_before_point(text: text) <= @precision - @scale
      end

      def digits_before_point(text:)
        whole_part = text.delete("+-").split(".").first

        whole_part.sub(/\A0+/, "").length
      end

      # Any text fits; only the length is limited, when the column has a limit.
      def within_length?(text:)
        @max_length.nil? || text.length <= @max_length
      end

      def boolean?(text:)
        BOOLEAN_WORDS.include?(text.downcase)
      end

      def date?(text:)
        match = DATE.match(text)
        return false unless match

        real_date?(year: match[1].to_i, month: match[2].to_i, day: match[3].to_i)
      end

      def time?(text:)
        match = TIME.match(text)
        return false unless match

        real_time?(hour: match[1].to_i, minute: match[2].to_i, second: match[3].to_i)
      end

      def timestamp?(text:)
        match = TIMESTAMP.match(text)
        return false unless match

        real_date?(year: match[1].to_i, month: match[2].to_i, day: match[3].to_i) &&
          real_time?(hour: match[4].to_i, minute: match[5].to_i, second: match[6].to_i)
      end

      def uuid?(text:)
        UUID.match?(text)
      end

      # Days 1 to 28 exist in every month, so the calendar is asked only for days 29 to 31.
      def real_date?(year:, month:, day:)
        return false unless year >= 1 && month.between?(1, 12) && day >= 1
        return true if day <= 28

        Date.valid_date?(year, month, day)
      end

      def real_time?(hour:, minute:, second:)
        hour < 24 && minute < 60 && second < 60
      end
    end
  end
end
