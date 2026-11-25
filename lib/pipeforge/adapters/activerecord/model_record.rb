# frozen_string_literal: true

module Pipeforge
  # One unsaved ActiveRecord record, wrapped for the run. It answers what the core asks of a model
  # record (see {RunProcessor::ChunkProcessor}): the errors of the model's own validations, and the write.
  class ActiveRecordModelRecord
    # @return [ActiveRecord::Base] the unsaved record
    attr_reader :record

    # The mistakes of the record, one for each column, with the shared codes: +value_missing+, +value_too_long+,
    # +value_not_unique+, +parent_missing+, +value_not_accepted+ (the target could not give the record the value),
    # +value_not_allowed+ and, for any other validation, +value_invalid+. After {#load} was refused by the
    # database they are its error instead, with +origin: :database+, the same codes, +value_out_of_range+ and
    # +database_error+; a callback that stopped the save is +value_invalid+ with +origin: :model+.
    #
    # @return [Hash{String, nil => ErrorCatalog::ColumnError}] target column name => its error, in the order the errors
    #   were added; the key nil is the record as a whole. Empty when there is none
    attr_reader :errors

    # @param record [ActiveRecord::Base] the unsaved record
    def initialize(record:)
      @record = record
      @errors = {}
    end

    # Adds an error to the record, unless its column already has one: the first error found for a column is the
    # one kept.
    #
    # @param error [ErrorCatalog::ColumnError] an error built by the {ErrorCatalog}
    # @raise [ArgumentError] the object was not built by the {ErrorCatalog}
    # @return [void]
    def add_error(error:)
      unless ErrorCatalog.error?(candidate: error)
        raise ArgumentError, ArgumentMessages::MESSAGES.fetch(:error_not_from_error_catalog).call(given_class: error.class)
      end

      return if @errors.key?(error.target_column_name)

      @errors[error.target_column_name] = error
    end

    # Runs the model's validations on the record and adds what they report, so a column that already has an
    # error (one the target added when it built the record, for example) is not reported again. It does not
    # clear the errors.
    #
    # @return [Boolean] true when the record has no error
    def valid?
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
      @errors = {}

      # requires_new makes a real transaction when none is open and a savepoint inside the dry run's,
      # so only this row is undone when the database refuses it.
      @record.class.transaction(requires_new: true) { @record.save!(validate: false) }

      true
    rescue ActiveRecord::StatementInvalid => database_error
      add_error(error: database_error_for(database_error: database_error))

      false
    rescue ActiveRecord::RecordNotSaved => not_saved_error
      # A callback of the model stopped the save.
      add_error(
        error: ErrorCatalog::ERRORS.fetch(:value_invalid_save_stopped)
          .call(origin: :model, target_column_name: nil, value: nil, native_message: not_saved_error.message)
      )

      false
    end

    # The values the record holds now: cast to the types of the columns, and after the model's validation
    # has run, so after its callbacks. They are what would be loaded. A column that was not given holds its
    # default, or nil.
    #
    # @return [Hash{String => Object}] column => value
    def attributes
      @record.attributes
    end

    # The values of {#attributes} as plain JSON types, which is what a failed row shows: a date is its ISO
    # text and a decimal a text.
    #
    # @return [Hash{String => Object}] column => value
    def json_attributes
      attributes.as_json
    end

    private

    # The error of the {ErrorCatalog} for one database exception, as the database found it (no column, no value),
    # with the text of the database as +native_message+.
    def database_error_for(database_error:)
      ErrorCatalog::ERRORS.fetch(database_key_of(database_error: database_error))
        # The column is not worked out from the message: the wording differs between databases.
        .call(origin: :database, target_column_name: nil, value: nil, native_message: database_error.message)
    end

    # The key of {ErrorCatalog::ERRORS} for a database exception: RecordNotUnique -> value_not_unique,
    # InvalidForeignKey -> parent_missing, NotNullViolation -> value_missing, ValueTooLong -> value_too_long,
    # RangeError -> value_out_of_range, anything else -> database_error.
    def database_key_of(database_error:)
      case database_error
      when ActiveRecord::RecordNotUnique then :value_not_unique
      when ActiveRecord::InvalidForeignKey then :parent_missing
      when ActiveRecord::NotNullViolation then :value_missing
      when ActiveRecord::ValueTooLong then :value_too_long
      when ActiveRecord::RangeError then :value_out_of_range
      else :database_error
      end
    end

    def add_model_errors
      @record.errors.each do |model_error|
        add_error(error: model_error_for(model_error: model_error))
      end
    end

    # The error of the {ErrorCatalog} for one error of the model's validations, with the value the record holds for
    # the column.
    def model_error_for(model_error:)
      key = key_of(model_error: model_error)
      target_column_name = target_column_name_of(model_error: model_error)
      failed_value = value_of(target_column_name: target_column_name)

      ErrorCatalog::ERRORS.fetch(key)
        .call(
          origin: :model, target_column_name: target_column_name, value: failed_value.as_json,
          **facts_of(model_error: model_error, key: key, failed_value: failed_value)
        )
    end

    # The value the record holds for a column; nil for the record as a whole and for an attribute that is not a column.
    def value_of(target_column_name:)
      return nil if target_column_name.nil? || !@record.has_attribute?(target_column_name)

      @record[target_column_name]
    end

    # The facts of the error: the text of the model as +native_message+, for every error of the model, and the facts
    # that its sentence uses.
    def facts_of(model_error:, key:, failed_value:)
      case key
      when :value_too_long
        {
          native_message: model_error.message, max_length: model_error.options[:count],
          length: failed_value.to_s.length
        }.compact
      when :value_invalid then {native_message: model_error.message, error_type: model_error.type}
      else {native_message: model_error.message}
      end
    end

    # The key of {ErrorCatalog::ERRORS} for an error of the model.
    def key_of(model_error:)
      case model_error.type
      when :blank then blank_key_of(model_error: model_error)
      when :too_long then :value_too_long
      when :taken then :value_not_unique
      else :value_invalid
      end
    end

    # The key of a blank error: +parent_missing+ for a +belongs_to+ association whose foreign key holds
    # a value, and +value_missing+ otherwise.
    def blank_key_of(model_error:)
      parent_reflection = parent_association_of(model_error: model_error)
      return :value_missing if parent_reflection.nil? || @record[parent_reflection.foreign_key].nil?

      :parent_missing
    end

    # The column the error is about: nil for an error on the record as a whole (+:base+), the foreign key column for
    # an error on a +belongs_to+ association, and the name of the attribute for any other error.
    def target_column_name_of(model_error:)
      return nil if model_error.attribute == :base

      parent_reflection = parent_association_of(model_error: model_error)
      return parent_reflection.foreign_key unless parent_reflection.nil?

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
