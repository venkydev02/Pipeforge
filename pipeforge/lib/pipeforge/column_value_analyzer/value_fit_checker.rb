# frozen_string_literal: true

module Pipeforge
  module ColumnValueAnalyzer
    # Decides whether one text fits the column and what it is cast to. It is a service: {.call} is a pure
    # function of its arguments and keeps nothing between calls.
    #
    # A text fits when the adapter can read it (it casts it to something other than nil) and the cast value
    # is within the limits of the column. Every type is cast, including a type the core knows no limit for.
    module ValueFitChecker
      # The outcome of checking one text.
      #   fits       whether the text fits the column
      #   casted_to  the cast value written as text, when that differs from the text (+abc+ in an integer
      #              column is +"0"+), whether the text fits or not; nil when it is the text itself
      FitCheck = Data.define(:fits, :casted_to)

      class << self
        # @param text [String] the value as it would be loaded, after the value mapping
        # @param target_column [String]
        # @param limits_checker [ColumnLimitsChecker] the checker of the target column
        # @param model_adapter [#cast_text] the adapter's object for the target table
        # @return [FitCheck]
        def call(text:, target_column:, limits_checker:, model_adapter:)
          cast_value = model_adapter.cast_text(column_name: target_column, text: text)
          # A nil cast means the adapter cannot read the text: it does not fit and there is no changed value.
          return FitCheck.new(fits: false, casted_to: nil) if cast_value.nil?

          # The changed value is given even when the text does not fit, because the cast value can be the
          # reason: 999.999 is cast to 1000.0 in a decimal column of scale 2.
          FitCheck.new(
            fits: limits_checker.violation_of(value: cast_value).nil?,
            casted_to: casted_to(text: text, cast_value: cast_value)
          )
        end

        private

        # The cast value written as text, when it differs from the text: +abc+ in an integer column is
        # +"0"+, +1,000+ is +"1"+, +2024-2-3+ in a date column is +"2024-02-03"+, and +no+ in a boolean
        # column is +"true"+. A form that only writes the same value differently also differs (+10.50+ is
        # +"10.5"+, a timestamp gains the +T+ and the zone).
        # A value that is not a string, a number, a boolean, a date or a time (an array, a range) is not
        # written as text, so it is never given.
        def casted_to(text:, cast_value:)
          return nil unless writable_as_text?(cast_value: cast_value)

          cast_text = written_as_text(cast_value: cast_value)

          (cast_text == text) ? nil : cast_text
        end

        def writable_as_text?(cast_value:)
          cast_value.is_a?(String) || cast_value.is_a?(Numeric) || [true, false].include?(cast_value) ||
            cast_value.respond_to?(:iso8601)
        end

        # A date or a time in ISO 8601, a decimal in plain notation, anything else as its own text.
        def written_as_text(cast_value:)
          return cast_value.iso8601 if cast_value.respond_to?(:iso8601)
          # Only a BigDecimal answers exponent; to_d would also match an Integer or a Float once ActiveSupport
          # is loaded, and their to_s takes no format.
          return cast_value.to_s("F") if cast_value.respond_to?(:exponent)

          cast_value.to_s
        end
      end
    end
  end
end
