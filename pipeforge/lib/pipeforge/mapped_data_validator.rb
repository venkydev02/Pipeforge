# frozen_string_literal: true

module Pipeforge
  # Checks the mapped columns a caller gives against what the engine needs to be correct: the
  # header of the source file and the schema of the target table. The engine runs it before
  # every stage that takes mapped columns.
  #
  # The mapped columns are keyed by target column; each entry names its source column. A source
  # column may feed several target columns: that is the consumer's choice and is not checked.
  #
  # Every mistake is collected and raised together, so the caller can fix them in one round. The
  # one exception is mapped columns that are not name: value entries at all, which stops the check
  # at once because there is nothing to read.
  #
  # @example
  #   validator = Pipeforge::MappedDataValidator.new(
  #     source_header_names: %w[Mail Age], target_column_names: %w[email age],
  #     required_target_column_names: %w[email], target_table: "users"
  #   )
  #   validator.call(mapped_columns: {"email" => {source_column: "Mail"}})  # => nil
  class MappedDataValidator
    # @param source_header_names [Array<String>] the column names of the source file, in file order
    # @param target_column_names [Array<String>] the columns of the target table that can be
    #   loaded into (the schema has no others)
    # @param required_target_column_names [Array<String>] the target columns that need a source
    #   column (see {TargetColumn})
    # @param target_table [String] the target table, named in the messages
    def initialize(source_header_names:, target_column_names:, required_target_column_names:, target_table:)
      @source_header_names = source_header_names
      @target_column_names = target_column_names
      @required_target_column_names = required_target_column_names
      @target_table = target_table
    end

    # @param mapped_columns [Hash{String => Hash}] target column => {source_column:,
    #   value_mapping:} (+value_mapping+ is optional: leave the key out for none; when the key is
    #   given the value must be a Hash, +nil+ included)
    # @return [nil] when every mapped column is usable and every required column is mapped
    # @raise [InvalidMappedColumnsError] +mapped_columns_not_name_value_entries+ alone when
    #   +mapped_columns+ is not a Hash; otherwise one entry for each mistake:
    #   +mapped_column_not_name_value_entries+, +target_column_not_in_schema+,
    #   +column_missing_source_column+, +mapped_column_not_in_file+,
    #   +value_mapping_not_name_value_entries+ or +required_column_unmapped+
    def call(mapped_columns:)
      reject_unreadable_mapped_columns(mapped_columns: mapped_columns)

      errors = []

      mapped_columns.each do |target_column, mapped_column|
        errors.concat(entry_errors(target_column: target_column, mapped_column: mapped_column))
      end
      errors.concat(required_column_errors(mapped_columns: mapped_columns))

      return if errors.empty?

      raise InvalidMappedColumnsError.new(errors: errors)
    end

    private

    # Stops at once when the mapped columns are not a Hash, because there are no entries to check.
    def reject_unreadable_mapped_columns(mapped_columns:)
      return if mapped_columns.is_a?(Hash)

      raise InvalidMappedColumnsError.single(
        code: :mapped_columns_not_name_value_entries,
        message: "the mapped columns must be a Hash of target column => {source_column:, ...}"
      )
    end

    # The mistakes of one entry. An entry that is not a Hash has nothing else to check.
    def entry_errors(target_column:, mapped_column:)
      unless mapped_column.is_a?(Hash)
        return [{
          code: :mapped_column_not_name_value_entries,
          message: "#{target_column} must be given as {source_column:, ...}",
          target_column: target_column
        }]
      end

      errors = []
      errors.concat(target_column_errors(target_column: target_column, mapped_column: mapped_column))
      errors.concat(source_column_errors(target_column: target_column, mapped_column: mapped_column))
      errors.concat(value_mapping_errors(target_column: target_column, mapped_column: mapped_column))
      errors
    end

    def target_column_errors(target_column:, mapped_column:)
      return [] if @target_column_names.include?(target_column)

      [{
        code: :target_column_not_in_schema,
        message: "#{target_column} is not a column of #{@target_table} that can be loaded",
        target_column: target_column,
        source_column: mapped_column[:source_column],
        table: @target_table
      }]
    end

    def source_column_errors(target_column:, mapped_column:)
      source_column = mapped_column[:source_column]

      if source_column.nil?
        return [{
          code: :column_missing_source_column,
          message: "#{target_column} has no source_column",
          target_column: target_column
        }]
      end

      return [] if @source_header_names.include?(source_column)

      [{
        code: :mapped_column_not_in_file,
        message: "#{target_column} is mapped to the source column #{source_column}, which is not in the file",
        target_column: target_column,
        source_column: source_column
      }]
    end

    # The value mapping is optional: leave the key out for no mapping. When the key is given the
    # value must be a Hash, so +nil+ is a mistake too. Its keys and values are not checked,
    # because a value may be mapped to anything, nil and blank included.
    def value_mapping_errors(target_column:, mapped_column:)
      return [] unless mapped_column.key?(:value_mapping)
      return [] if mapped_column[:value_mapping].is_a?(Hash)

      [{
        code: :value_mapping_not_name_value_entries,
        message: "the value_mapping of #{target_column} must be a Hash of value in the file => value to load",
        target_column: target_column
      }]
    end

    # A required target column that has no entry at all. An entry that exists but names no source
    # column is already reported by +column_missing_source_column+.
    def required_column_errors(mapped_columns:)
      errors = []

      @required_target_column_names.each do |target_column|
        next if mapped_columns.key?(target_column)

        errors << {
          code: :required_column_unmapped,
          message: "#{target_column} is required but no source column is mapped to it",
          target_column: target_column
        }
      end

      errors
    end
  end
end
