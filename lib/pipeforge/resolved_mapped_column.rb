# frozen_string_literal: true

module Pipeforge
  # One of the consumer's mapped columns (an entry of the +mapped_columns+ Hash) after the engine has checked it and
  # looked up its target column in the schema. The column values stage takes these and not the consumer's Hash: they
  # say which source column feeds a target column, how the values of the file are changed on the way, and the column
  # of the target table it fills. The consumer writes the first two as a plain Hash and {.from_entry} reads that Hash.
  #   source_column  String                  the source column the values are read from
  #   value_mapping  Hash{String => Object}  the value in the file (a text) => the value to load; empty when there is
  #                                          none
  #   target_column  TargetColumn            the column of the target table, which gives its type and limits
  ResolvedMappedColumn = Data.define(:source_column, :value_mapping, :target_column) do
    # @param entry [Hash] what the consumer wrote: +{source_column:, value_mapping: (optional)}+; any other key is
    #   not read
    # @param target_column [TargetColumn] the column of the target table that the entry is for
    # @return [ResolvedMappedColumn] the keys of the value mapping turned into text, because the values of the file are
    #   text (+1+ and +"1"+ are the same key, and the later one is used); the entry is not changed
    # @raise [KeyError] the entry has no +source_column+; {MappedDataValidator} has already refused such an entry
    def self.from_entry(entry:, target_column:)
      new(
        source_column: entry.fetch(:source_column),
        value_mapping: entry.fetch(:value_mapping, {}).transform_keys(&:to_s),
        target_column: target_column
      )
    end
  end
end
