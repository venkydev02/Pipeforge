# frozen_string_literal: true

module Pipeforge
  # The consumer's mapped columns, checked against the header of the source file and the columns of the target table,
  # and resolved for the stages that take them. The consumer writes a Hash of target column name => entry, and an entry
  # is {source_column_name: ..., value_mapping: ...} (the value mapping is optional). A key written as a String is read
  # as the Symbol, and the caller's Hash is not changed.
  #
  # A mapping with the wrong shape is a mistake in the call: building the object raises an ArgumentError that lists
  # every such mistake. A mapping with the right shape that does not fit the file or the table is a mistake about the
  # data: {#resolved_mapped_columns!} raises one error that lists every one, so the caller can fix them in one round. A source column may feed several target
  # columns: that is the consumer's choice and is not checked.
  #
  # @example
  #   checked_mapping = MappedColumns.new(
  #     mapped_columns: {email: {source_column_name: "Mail"}}, source_header_names: %w[Mail Age],
  #     target_columns: target_schema.columns
  #   )
  #   checked_mapping.resolved_mapped_columns! # => {"email" => #<data ResolvedMappedColumn ...>}
  class MappedColumns
    # The keys of an entry that the engine reads.
    ENTRY_KEYS = %i[source_column_name value_mapping].freeze
    ENTRY_KEYS_TEXT = ENTRY_KEYS.map(&:inspect).join(" and ").freeze

    # @param mapped_columns [Object] what the consumer gave: target column name (a Symbol or a String) => entry
    # @param source_header_names [Array<String>] the column names of the source file, in file order
    # @param target_columns [Array<TargetColumn>] the columns of the target table that can be loaded into
    # @raise [ArgumentError] +mapped_columns+ is not a Hash (alone); otherwise every shape mistake in one message: a
    #   target column name that is neither a Symbol nor a String, an entry that is not a Hash, a key of an entry other
    #   than +source_column_name+ and +value_mapping+, or a +value_mapping+ that is neither a Hash nor nil
    def initialize(mapped_columns:, source_header_names:, target_columns:)
      reject_wrong_shape(mapped_columns: mapped_columns)

      @source_header_names = source_header_names
      @target_columns_by_name = {}
      target_columns.each { |target_column| @target_columns_by_name[target_column.name] = target_column }
      @entries_by_target_column_name = normalized_copy_of(mapped_columns: mapped_columns)
    end

    # Checks the mapped columns against the file and the table, and resolves them.
    #
    # @return [Hash{String => ResolvedMappedColumn}] the mapping resolved against the target columns (the target column
    #   names as Strings, in the order the consumer gave them)
    # @raise [InvalidMappedColumnsError] one entry for each data mistake, in this order: each mapped column first
    #   (+target_column_not_in_schema+, then +column_missing_source_column+ or +mapped_column_not_in_file+), then the
    #   required columns that have no entry (+required_column_unmapped+)
    def resolved_mapped_columns!
      found_errors = data_errors
      raise InvalidMappedColumnsError.new(errors: found_errors) unless found_errors.empty?

      build_resolved_mapped_columns
    end

    private

    # Stops with every shape mistake in one message. That the mapped columns are a Hash is checked first and reported
    # alone, because without a Hash there is nothing else to read. The input is checked as it was given, so a name or a
    # key may be a Symbol or a String.
    def reject_wrong_shape(mapped_columns:)
      unless mapped_columns.is_a?(Hash)
        raise ArgumentError, "mapped_columns must be a Hash of target column name => entry, got #{mapped_columns.class}"
      end

      problems = []

      mapped_columns.each do |target_column_name, entry|
        problems.concat(shape_problems_of(target_column_name: target_column_name, entry: entry))
      end

      raise ArgumentError, problems.join("; ") unless problems.empty?
    end

    # The shape mistakes of one entry. The name and the entry are checked independently, so both are reported; the keys
    # of the entry can be checked only when it is a Hash.
    def shape_problems_of(target_column_name:, entry:)
      problems = []

      unless symbol_or_string?(value: target_column_name)
        problems << "the key #{target_column_name.inspect} of mapped_columns must be a Symbol or a String"
      end

      if entry.is_a?(Hash)
        problems.concat(key_problems_of(target_column_name: target_column_name, entry: entry))
      else
        problems << "#{target_column_name} must be given as {source_column_name: ...}, got #{entry.class}"
      end

      problems
    end

    def key_problems_of(target_column_name:, entry:)
      problems = []

      entry.each do |key, value|
        if entry_key?(key: key)
          # A value mapping that is given must be a Hash, or nil for no mapping. What is inside the Hash is not checked,
          # because a value may be mapped to anything, even nil or a blank.
          if key.to_sym == :value_mapping && !value.nil? && !value.is_a?(Hash)
            problems << "the value_mapping of #{target_column_name} must be a Hash of value in the file => value to " \
                        "load, got #{value.class}"
          end
        else
          problems << "#{target_column_name} has the unknown key #{key.inspect}; the keys are #{ENTRY_KEYS_TEXT}"
        end
      end

      problems
    end

    def entry_key?(key:)
      symbol_or_string?(value: key) && ENTRY_KEYS.include?(key.to_sym)
    end

    def symbol_or_string?(value:)
      value.is_a?(Symbol) || value.is_a?(String)
    end

    # A copy of the checked mapped columns with the target column names as Strings (the names of the table's columns
    # are Strings), the keys of an entry as Symbols and the keys of a value mapping as text (the values of the file are
    # text, so a key written as 1 has to match the text "1"). A value mapping that is nil or left out becomes an empty
    # one. Of two keys that give the same text, the later one is kept.
    def normalized_copy_of(mapped_columns:)
      entries_by_target_column_name = {}

      mapped_columns.each do |target_column_name, entry|
        entries_by_target_column_name[target_column_name.to_s] = normalized_entry_of(entry: entry)
      end

      entries_by_target_column_name
    end

    def normalized_entry_of(entry:)
      normalized_entry = entry.transform_keys(&:to_sym)
      normalized_entry[:value_mapping] = Hash(normalized_entry[:value_mapping]).transform_keys(&:to_s)

      normalized_entry
    end

    def data_errors
      found_errors = []

      @entries_by_target_column_name.each do |target_column_name, entry|
        found_errors << target_column_error(target_column_name: target_column_name)
        found_errors << source_column_error(target_column_name: target_column_name, entry: entry)
      end
      found_errors.concat(required_column_errors)

      found_errors.compact
    end

    # The error of an entry whose target column is not a column of the table, or nil.
    def target_column_error(target_column_name:)
      return if @target_columns_by_name.key?(target_column_name)

      InvalidMappedColumnsError::ENTRIES.fetch(:target_column_not_in_schema).call(target_column_name: target_column_name)
    end

    # The error of an entry that names no source column, or one that is not in the file, or nil.
    def source_column_error(target_column_name:, entry:)
      source_column_name = entry[:source_column_name]

      if source_column_name.nil?
        InvalidMappedColumnsError::ENTRIES.fetch(:column_missing_source_column).call(target_column_name: target_column_name)
      elsif !@source_header_names.include?(source_column_name)
        InvalidMappedColumnsError::ENTRIES.fetch(:mapped_column_not_in_file).call(
          target_column_name: target_column_name, source_column_name: source_column_name
        )
      end
    end

    # A required target column that has no entry at all. An entry that exists but names no source column is already
    # reported by +column_missing_source_column+.
    def required_column_errors
      found_errors = []

      @target_columns_by_name.each_value do |target_column|
        next unless target_column.required
        next if @entries_by_target_column_name.key?(target_column.name)

        found_errors << InvalidMappedColumnsError::ENTRIES.fetch(:required_column_unmapped).call(
          target_column_name: target_column.name
        )
      end

      found_errors
    end

    def build_resolved_mapped_columns
      resolved_mapped_columns = {}

      @entries_by_target_column_name.each do |target_column_name, entry|
        resolved_mapped_columns[target_column_name] = ResolvedMappedColumn.new(
          source_column_name: entry[:source_column_name], value_mapping: entry[:value_mapping],
          target_column: @target_columns_by_name.fetch(target_column_name)
        )
      end

      resolved_mapped_columns
    end
  end
end
