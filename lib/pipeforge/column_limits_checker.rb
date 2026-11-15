# frozen_string_literal: true

module Pipeforge
  # Whether a value is within the limits of one target column: the size of an integer, the digits of a
  # decimal, the range of a float, the length of a string and the labels of an enum. The value is the one
  # the adapter cast (an Integer, a Float or a decimal for a number).
  #
  # @example
  #   limits = ColumnLimitsChecker.new(type: "integer", limit: 2)
  #   limits.violation_of(value: 40_000)  # => #<data Violation code=:value_out_of_range, ...>
  #   limits.violation_of(value: 100)     # => nil
  class ColumnLimitsChecker
    # What is wrong with a value that is outside the limits.
    #   code    +:value_too_long+, +:value_out_of_range+ or +:value_not_allowed+
    #   detail  a clause that says it, such as "the value has 5 characters, more than the 3 allowed";
    #           it never quotes the value
    Violation = Data.define(:code, :detail)

    # The types that have a limit, each with the check that applies to its values. A value of any other
    # type (a boolean, a date, a uuid, json, and so on) has no limit.
    CHECKS = {
      "string" => :length_violation,
      "text" => :length_violation,
      "integer" => :integer_violation,
      "decimal" => :decimal_violation,
      "float" => :float_violation
    }.freeze

    # The size in bytes of an integer column that has no limit.
    DEFAULT_INTEGER_LIMIT = 4

    # Builds the checker of a target column from its type and limits.
    #
    # @param target_column [TargetColumn]
    # @return [ColumnLimitsChecker]
    def self.for(target_column:)
      new(
        type: target_column.type,
        limit: target_column.limit,
        is_signed: target_column.is_signed,
        max_length: target_column.max_length,
        precision: target_column.precision,
        scale: target_column.scale,
        enum_labels: target_column.enum_labels
      )
    end

    # @param type [String, Symbol, nil] the type of the target column; a type with no limit, or nil, has none
    # @param limit [Integer, nil] integer: the size in bytes, 4 when not given; float: the significand bits, 24 or
    #   less for single precision and anything else for double
    # @param is_signed [Boolean, nil] false for an integer column that holds no negative number; true, or nil when
    #   not given, for one that does
    # @param max_length [Integer, nil] the length of a string or text column
    # @param precision [Integer, nil] the digits of a decimal column
    # @param scale [Integer, nil] the digits of a decimal column after the point; 0 when not given
    # @param enum_labels [Array<String>, nil] the labels of an enum column, which accepts these and nothing else
    def initialize(type:, limit: nil, is_signed: nil, max_length: nil, precision: nil, scale: nil, enum_labels: nil)
      @type = type.to_s
      @enum_labels = enum_labels
      @limit = limit
      @is_signed = is_signed
      @max_length = max_length
      @precision = precision
      # A decimal declared with no scale keeps no digits after the point (DECIMAL(10) is DECIMAL(10, 0)), and the
      # checks below do arithmetic on it.
      @scale = scale || 0
    end

    # @param value [Object] the value the adapter cast for the column
    # @return [Violation, nil] nil when the value is within the limits, or when the type has no limit
    def violation_of(value:)
      return enum_violation(value: value) unless @enum_labels.nil?

      check = CHECKS[@type]
      return nil if check.nil?

      send(check, value: value)
    end

    private

    # An enum column accepts its labels. A value the database stores for a label is not a label.
    def enum_violation(value:)
      return nil if @enum_labels.include?(value.to_s)

      Violation.new(code: :value_not_allowed, detail: "the value is not one of #{@enum_labels.join(", ")}")
    end

    # Only the length is limited, and only when the column has a limit; it is counted in characters.
    def length_violation(value:)
      length = value.to_s.length
      return nil if @max_length.nil? || length <= @max_length

      Violation.new(
        code: :value_too_long, detail: "the value has #{length} characters, more than the #{@max_length} allowed"
      )
    end

    def integer_violation(value:)
      bytes = @limit || DEFAULT_INTEGER_LIMIT
      return nil if value.between?(*integer_range(bytes: bytes))

      Violation.new(code: :value_out_of_range, detail: "the value does not fit in #{bytes} bytes")
    end

    # The smallest and the largest whole number of a column of that many bytes: an unsigned column
    # starts at 0 and reaches twice as high.
    def integer_range(bytes:)
      bits = 8 * bytes
      # nil (not given) is a signed column; only false means unsigned.
      return [0, 2**bits - 1] if @is_signed == false

      [-(2**(bits - 1)), 2**(bits - 1) - 1]
    end

    # The digits before the point, once the number is rounded to the scale, must fit in precision - scale.
    # A number that is not finite is left alone.
    def decimal_violation(value:)
      return nil if @precision.nil? || !value.finite?

      allowed_digits = @precision - @scale
      return nil if digits_before_point(number: value.to_r) <= allowed_digits

      Violation.new(
        code: :value_out_of_range, detail: "the value has more than #{allowed_digits} digits before the point"
      )
    end

    def digits_before_point(number:)
      # Rounded first because the database stores the rounded number, which can gain a digit before the
      # point: 999.999 in a column of scale 2 is stored as 1000.00.
      number.round(@scale).truncate.abs.to_s.sub(/\A0+/, "").length
    end

    # A float past the largest the column holds, or infinite. NaN is left alone.
    def float_violation(value:)
      number = value.to_f
      # 1e9999 is cast to Infinity, which is out of range; NaN is not.
      return nil if number.nan?
      return nil if number.finite? && number.abs <= Utilities.largest_float(limit: @limit)

      Violation.new(code: :value_out_of_range, detail: "the value is larger than a float of this column can hold")
    end
  end
end
