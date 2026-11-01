# frozen_string_literal: true

module Pipeforge
  # One unsaved ActiveRecord record, wrapped for the run. It answers what the core asks of a model
  # record (see {RowCandidate#model_record}): the errors of the model's own validations.
  class ActiveRecordModelRecord
    # @return [ActiveRecord::Base] the unsaved record
    attr_reader :record

    # The mistakes that the last {#valid?} found, with the shared codes: +value_missing+,
    # +value_too_long+, +value_not_unique+, +parent_missing+, +value_not_allowed+ (an enum label the
    # model does not know) and, for any other validation, +value_invalid+.
    #
    # @return [Array<Hash>] one entry {code:, message:, target_column:} for each mistake; empty before
    #   {#valid?} is called and when the model finds none
    attr_reader :errors

    # @param record [ActiveRecord::Base] the unsaved record
    # @param unknown_enum_labels [Hash{String => String}] enum column => the label the model does not
    #   know, set aside when the record was built
    def initialize(record:, unknown_enum_labels:)
      @record = record
      @unknown_enum_labels = unknown_enum_labels
      @errors = []
    end

    # Runs the model's validations on the record and keeps what they report in {#errors}. A column
    # whose enum label the model does not know is reported once, as +value_not_allowed+, and not
    # again by the model's own validations.
    #
    # @return [Boolean] true when the model finds no mistake
    def valid?
      @errors = []
      add_unknown_enum_label_errors
      add_model_errors unless @record.valid?

      @errors.empty?
    end

    # The values the record holds now: cast to the types of the columns, and after the model's validation
    # has run, so after its callbacks. They are what would be loaded. An enum label the model does not
    # know is included as it was given.
    #
    # @return [Hash{String => Object}] column => value
    def attributes
      # The record cannot hold a label it does not know, so it is added back as it was given.
      @record.attributes.merge(@unknown_enum_labels)
    end

    private

    def add_unknown_enum_label_errors
      @unknown_enum_labels.each do |column_name, label|
        @errors << {
          code: :value_not_allowed,
          message: "#{column_name}: #{label} is not a label or value of the enum",
          target_column: column_name
        }
      end
    end

    def add_model_errors
      @record.errors.each do |model_error|
        target_column = target_column_of(model_error: model_error)
        next if @unknown_enum_labels.key?(target_column)

        @errors << {
          code: code_of(model_error: model_error),
          message: model_error.full_message,
          target_column: target_column
        }
      end
    end

    def code_of(model_error:)
      case model_error.type
      when :blank then blank_code_of(model_error: model_error)
      when :too_long then :value_too_long
      when :taken then :value_not_unique
      else :value_invalid
      end
    end

    # The code of a blank error: +parent_missing+ for a +belongs_to+ association whose foreign key holds
    # a value, and +value_missing+ otherwise.
    def blank_code_of(model_error:)
      reflection = parent_association_of(model_error: model_error)
      return :value_missing if reflection.nil? || @record[reflection.foreign_key].nil?

      :parent_missing
    end

    # The column the error is about: the foreign key column for an error on a +belongs_to+
    # association, nil for an error on the record as a whole.
    def target_column_of(model_error:)
      return nil if model_error.attribute == :base

      reflection = parent_association_of(model_error: model_error)
      return reflection.foreign_key unless reflection.nil?

      model_error.attribute.to_s
    end

    # The +belongs_to+ association that the error is on, with a single foreign key column; nil when it
    # is on anything else.
    def parent_association_of(model_error:)
      reflection = @record.class.reflect_on_association(model_error.attribute)
      return nil unless reflection&.belongs_to? && reflection.foreign_key.is_a?(String)

      reflection
    end
  end
end
