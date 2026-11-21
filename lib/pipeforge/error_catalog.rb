# frozen_string_literal: true

module Pipeforge
  # The kinds of error of a row, each written once. {ERRORS} is keyed by the code and its kind joined
  # (+:value_out_of_range_bytes+, or the code alone when it has no kind). The value of a key is a function that takes
  # +origin:+ (where the mistake was found), +target_column_name:+, the failed +value+ (in JSON types, or nil when there
  # is none) and the facts its sentence uses, and returns the error as a {ColumnError}.
  #
  # Only these functions can make a {ColumnError}: the class cannot be named or built outside the module, so
  # {.error?} is how another class asks whether an object is one. A failed row holds the error objects, and
  # +FailedRow#to_h+ gives each of them as the Hash that +ColumnError#to_h+ gives, with the seven keys.
  #
  # A function lists every fact it accepts as a keyword, so a fact it does not know is refused. The kinds that the
  # database can also report take +native_message+ as an optional fact.
  #
  # The message is always ours, never the text of the model or of the database. That text, when there is one, is the
  # fact +native_message+, and a few sentences end with it in brackets.
  #
  # @example
  #   error = Pipeforge::ErrorCatalog::ERRORS[:value_too_long].call(
  #     origin: :schema, target_column_name: "status", value: "x" * 34, length: 34, max_length: 20
  #   )
  #   error.to_h  # => {origin: :schema, code: :value_too_long, kind: nil, target_column_name: "status",
  #               #     message: "status: the value has 34 characters, more than the 20 allowed",
  #               #     details: {length: 34, max_length: 20}, value: "xxxxxxxx..."}
  module ErrorCatalog
    # One error of a row, as a function of {ERRORS} builds it.
    #   origin              where the mistake was found: +:schema+, +:model+ or +:database+
    #   code                the stable code of the mistake
    #   kind                which case of the code, or nil
    #   target_column_name  the column it is about; nil for the record as a whole
    #   message             what is wrong, always ours, with the column first
    #   details             the facts of the mistake, as a frozen Hash
    #   value               the value that failed, in JSON types; nil when there is none
    ColumnError = Data.define(:origin, :code, :kind, :target_column_name, :message, :details, :value) do
      private_class_method :new

      # The one way to make an error, used by {ErrorCatalog.error}.
      #
      # @return [ColumnError]
      def self.build(origin:, code:, kind:, target_column_name:, message:, details:, value:)
        new(
          origin: origin, code: code, kind: kind, target_column_name: target_column_name, message: message,
          details: details.freeze, value: value
        )
      end
    end
    private_constant :ColumnError

    ERRORS = {
      value_missing: ->(origin:, target_column_name:, value:, native_message: nil) {
        ErrorCatalog.error(
          code: :value_missing, kind: nil, sentence: "the value is required but empty",
          origin: origin, target_column_name: target_column_name, value: value, details: {native_message: native_message}.compact
        )
      },
      parent_missing: ->(origin:, target_column_name:, value:, native_message: nil) {
        ErrorCatalog.error(
          code: :parent_missing, kind: nil, sentence: "the parent row does not exist",
          origin: origin, target_column_name: target_column_name, value: value, details: {native_message: native_message}.compact
        )
      },
      value_not_unique: ->(origin:, target_column_name:, value:, native_message: nil) {
        ErrorCatalog.error(
          code: :value_not_unique, kind: nil, sentence: "a row with the same value already exists",
          origin: origin, target_column_name: target_column_name, value: value, details: {native_message: native_message}.compact
        )
      },
      # The most specific sentence the given facts allow.
      value_too_long: ->(origin:, target_column_name:, value:, length: nil, max_length: nil, native_message: nil) {
        sentence = if !length.nil? && !max_length.nil?
          "the value has #{length} characters, more than the #{max_length} allowed"
        elsif !max_length.nil?
          "the value is longer than the #{max_length} characters allowed"
        else
          "the value is longer than its column allows"
        end

        ErrorCatalog.error(
          code: :value_too_long, kind: nil, sentence: sentence, origin: origin, target_column_name: target_column_name, value: value,
          details: {length: length, max_length: max_length, native_message: native_message}.compact
        )
      },
      value_out_of_range_bytes: ->(origin:, target_column_name:, value:, bytes:) {
        ErrorCatalog.error(
          code: :value_out_of_range, kind: :bytes, sentence: "the value does not fit in #{bytes} bytes",
          origin: origin, target_column_name: target_column_name, value: value, details: {bytes: bytes}
        )
      },
      value_out_of_range_digits: ->(origin:, target_column_name:, value:, allowed_digits:) {
        ErrorCatalog.error(
          code: :value_out_of_range, kind: :digits,
          sentence: "the value has more than #{allowed_digits} digits before the point",
          origin: origin, target_column_name: target_column_name, value: value, details: {allowed_digits: allowed_digits}
        )
      },
      value_out_of_range_float: ->(origin:, target_column_name:, value:) {
        ErrorCatalog.error(
          code: :value_out_of_range, kind: :float,
          sentence: "the value is larger than a float of this column can hold",
          origin: origin, target_column_name: target_column_name, value: value, details: {}
        )
      },
      value_out_of_range: ->(origin:, target_column_name:, value:, native_message: nil) {
        ErrorCatalog.error(
          code: :value_out_of_range, kind: nil, sentence: "the value is outside what its column holds",
          origin: origin, target_column_name: target_column_name, value: value, details: {native_message: native_message}.compact
        )
      },
      value_not_allowed: ->(origin:, target_column_name:, value:, labels:) {
        ErrorCatalog.error(
          code: :value_not_allowed, kind: nil, sentence: "the value is not one of #{labels.join(", ")}",
          origin: origin, target_column_name: target_column_name, value: value, details: {labels: labels}
        )
      },
      value_not_accepted_not_castable: ->(origin:, target_column_name:, value:) {
        ErrorCatalog.error(
          code: :value_not_accepted, kind: :not_castable, sentence: "the value cannot be given to the model",
          origin: origin, target_column_name: target_column_name, value: value, details: {}
        )
      },
      value_not_accepted_enum_label: ->(origin:, target_column_name:, value:) {
        ErrorCatalog.error(
          code: :value_not_accepted, kind: :enum_label, sentence: "the value is not a label of the enum",
          origin: origin, target_column_name: target_column_name, value: value, details: {}
        )
      },
      value_not_accepted_polymorphic_type: ->(origin:, target_column_name:, value:) {
        ErrorCatalog.error(
          code: :value_not_accepted, kind: :polymorphic_type,
          sentence: "the value is not a model of the application",
          origin: origin, target_column_name: target_column_name, value: value, details: {}
        )
      },
      value_invalid: ->(origin:, target_column_name:, value:, native_message:, error_type: nil) {
        ErrorCatalog.error(
          code: :value_invalid, kind: nil, sentence: "the model does not accept the value (#{native_message})",
          origin: origin, target_column_name: target_column_name, value: value, details: {native_message: native_message, error_type: error_type}.compact
        )
      },
      value_invalid_save_stopped: ->(origin:, target_column_name:, value:, native_message:) {
        ErrorCatalog.error(
          code: :value_invalid, kind: :save_stopped,
          sentence: "a callback of the model stopped the save (#{native_message})",
          origin: origin, target_column_name: target_column_name, value: value, details: {native_message: native_message}
        )
      },
      database_error: ->(origin:, target_column_name:, value:, native_message:) {
        ErrorCatalog.error(
          code: :database_error, kind: nil, sentence: "the database refused the row (#{native_message})",
          origin: origin, target_column_name: target_column_name, value: value, details: {native_message: native_message}
        )
      }
    }.freeze

    class << self
      # The error with its message; the one place that joins the column and the sentence.
      #
      # @param origin [Symbol] where the mistake was found: +:schema+, +:model+ or +:database+
      # @param code [Symbol] the stable code of the mistake
      # @param kind [Symbol, nil] which case of the code, or nil
      # @param sentence [String] what is wrong, without the column
      # @param target_column_name [String, nil] the column it is about; nil for the record as a whole
      # @param value [Object, nil] the value that failed, in JSON types; nil when there is none
      # @param details [Hash] the facts of the mistake
      # @return [ColumnError]
      def error(origin:, code:, kind:, sentence:, target_column_name:, value:, details:)
        message = sentence
        message = "#{target_column_name}: #{sentence}" unless target_column_name.nil?

        ColumnError.build(
          origin: origin, code: code, kind: kind, target_column_name: target_column_name, message: message,
          details: details, value: value
        )
      end

      # @param candidate [Object] anything
      # @return [Boolean] true when the object is an error built by this module
      def error?(candidate:)
        candidate.is_a?(ColumnError)
      end
    end
  end
end
