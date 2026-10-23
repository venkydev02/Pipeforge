# frozen_string_literal: true

module Pipeforge
  # Checks the mapped columns a caller gives against the two things they must fit: the header of
  # the source file and the schema of the target table (ADR-18). The engine runs it on every
  # stage that takes mapped columns, so the stages that follow can trust them.
  #
  # Every mistake is collected and raised together, so the caller can fix them in one round. A
  # column that is wrong on both sides gets one entry for each side.
  #
  # @example
  #   validator = Pipeforge::MappedDataValidator.new(
  #     source_header_names: %w[Mail Age], target_column_names: %w[email age], target_table: "users"
  #   )
  #   validator.call(mapped_columns: {"Mail" => {target_column: "email"}})  # => nil
  class MappedDataValidator
    # @param source_header_names [Array<String>] the column names of the source file, in file order
    # @param target_column_names [Array<String>] the columns of the target table that can be
    #   loaded into (the schema has no others)
    # @param target_table [String] the target table, named in the messages
    def initialize(source_header_names:, target_column_names:, target_table:)
      @source_header_names = source_header_names
      @target_column_names = target_column_names
      @target_table = target_table
    end

    # @param mapped_columns [Hash{String => Hash}] source column => {target_column:, ...}
    # @return [nil] when every mapped column is usable
    # @raise [InvalidMappedColumnsError] one entry for each mistake: +column_missing_target_column+,
    #   +mapped_column_not_in_file+ or +target_column_not_in_schema+
    def call(mapped_columns:)
      errors = []

      mapped_columns.each do |source_column, mapped_column|
        errors.concat(source_column_errors(source_column: source_column))
        errors.concat(target_column_errors(source_column: source_column, mapped_column: mapped_column))
      end

      return if errors.empty?

      raise InvalidMappedColumnsError.new(errors: errors)
    end

    private

    def source_column_errors(source_column:)
      return [] if @source_header_names.include?(source_column)

      [{
        code: :mapped_column_not_in_file,
        message: "mapped source column #{source_column} is not in the file",
        source_column: source_column
      }]
    end

    def target_column_errors(source_column:, mapped_column:)
      target_column_name = mapped_column[:target_column]

      if target_column_name.nil?
        return [{
          code: :column_missing_target_column,
          message: "#{source_column} has no target_column",
          source_column: source_column
        }]
      end

      return [] if @target_column_names.include?(target_column_name)

      [{
        code: :target_column_not_in_schema,
        message: "#{source_column} is mapped to #{target_column_name}, which is not a column of " \
                 "#{@target_table} that can be loaded",
        source_column: source_column,
        target_column: target_column_name,
        table: @target_table
      }]
    end
  end
end
