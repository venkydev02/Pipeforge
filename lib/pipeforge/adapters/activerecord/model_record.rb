# frozen_string_literal: true

module Pipeforge
  # One unsaved ActiveRecord record, wrapped for the run. It answers what the core asks of a model
  # record (see {RunProcessor::RowCandidate#model_record}): the errors of the model's own validations, and the write.
  class ActiveRecordModelRecord
    # @return [ActiveRecord::Base] the unsaved record
    attr_reader :record

    # The mistakes that the last {#valid?} found, with the shared codes: +value_missing+,
    # +value_too_long+, +value_not_unique+, +parent_missing+, +value_not_allowed+ (an enum label the
    # model does not know), +value_not_json+ (a text in a json column that is not JSON) and, for any
    # other validation, +value_invalid+. After {#load} was refused
    # by the database they are its entries instead, with +origin: :database+, the same codes,
    # +value_out_of_range+ and +database_error+; a callback that stopped the save is +value_invalid+ with
    # +origin: :model+.
    #
    # @return [Array<Hash>] one entry {origin:, code:, message:, target_column:} for each mistake, with
    #   +origin+ +:model+ or +:database+; empty before
    #   {#valid?} is called and when there is none
    attr_reader :errors

    # @param record [ActiveRecord::Base] the unsaved record
    # @param unknown_enum_labels [Hash{String => String}] enum column => the label the model does not
    #   know, set aside when the record was built
    # @param invalid_json_texts [Hash{String => String}] json column => the text that is not JSON, set aside
    #   when the record was built
    def initialize(record:, unknown_enum_labels:, invalid_json_texts:)
      @record = record
      @unknown_enum_labels = unknown_enum_labels
      @invalid_json_texts = invalid_json_texts
      @errors = []
    end

    # Runs the model's validations on the record and keeps what they report in {#errors}. A column
    # whose enum label the model does not know is reported once, as +value_not_allowed+, and not
    # again by the model's own validations. A json column whose text is not JSON is reported as
    # +value_not_json+.
    #
    # @return [Boolean] true when the model finds no mistake
    def valid?
      @errors = []
      add_unknown_enum_label_errors
      add_invalid_json_text_errors
      add_model_errors unless @record.valid?

      @errors.empty?
    end

    # Writes the record to its table in its own transaction (a savepoint when a transaction is
    # already open). The model's validations are not run again. A mistake from the database is kept
    # in {#errors} with +origin: :database+ and nothing of this row is kept. A callback of the model that
    # stops the save is kept with +origin: :model+.
    #
    # @return [Boolean] true when the row was written
    def load
      @errors = []

      # requires_new makes a real transaction when none is open and a savepoint inside the dry run's,
      # so only this row is undone when the database refuses it.
      @record.class.transaction(requires_new: true) { @record.save!(validate: false) }

      true
    rescue ActiveRecord::StatementInvalid => database_error
      @errors << database_error_entry(database_error: database_error)

      false
    rescue ActiveRecord::RecordNotSaved => not_saved_error
      # A callback of the model stopped the save.
      @errors << {origin: :model, code: :value_invalid, message: not_saved_error.message, target_column: nil}

      false
    end

    # The values the record holds now: cast to the types of the columns, and after the model's validation
    # has run, so after its callbacks. They are what would be loaded. An enum label the model does not
    # know and a text that is not JSON are included as they were given.
    #
    # @return [Hash{String => Object}] column => value
    def attributes
      # The record cannot hold a label it does not know or a text that is not JSON, so they are added back as
      # they were given.
      @record.attributes.merge(@unknown_enum_labels).merge(@invalid_json_texts)
    end

    private

    # The entry {origin: :database, code:, message:, target_column:} for one database exception:
    # RecordNotUnique -> value_not_unique, InvalidForeignKey -> parent_missing,
    # NotNullViolation -> value_missing, ValueTooLong -> value_too_long,
    # RangeError -> value_out_of_range, anything else -> database_error (native message kept).
    def database_error_entry(database_error:)
      {
        origin: :database,
        code: database_code_of(database_error: database_error),
        message: database_error.message,
        # The column is not worked out from the message: the wording differs between databases.
        target_column: nil
      }
    end

    def database_code_of(database_error:)
      case database_error
      when ActiveRecord::RecordNotUnique then :value_not_unique
      when ActiveRecord::InvalidForeignKey then :parent_missing
      when ActiveRecord::NotNullViolation then :value_missing
      when ActiveRecord::ValueTooLong then :value_too_long
      when ActiveRecord::RangeError then :value_out_of_range
      else :database_error
      end
    end

    def add_unknown_enum_label_errors
      @unknown_enum_labels.each do |column_name, label|
        @errors << {
          origin: :model,
          code: :value_not_allowed,
          message: "#{column_name}: #{label} is not a label or value of the enum",
          target_column: column_name
        }
      end
    end

    def add_invalid_json_text_errors
      @invalid_json_texts.each_key do |column_name|
        @errors << {
          origin: :model,
          code: :value_not_json,
          message: "#{column_name}: the text is not JSON",
          target_column: column_name
        }
      end
    end

    def add_model_errors
      @record.errors.each do |model_error|
        target_column = target_column_of(model_error: model_error)
        next if @unknown_enum_labels.key?(target_column)

        @errors << {
          origin: :model,
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
