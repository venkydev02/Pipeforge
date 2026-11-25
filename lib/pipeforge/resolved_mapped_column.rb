# frozen_string_literal: true

module Pipeforge
  # One of the consumer's mapped columns (an entry of the +mapped_columns+ Hash) after the engine has checked it and
  # looked up its target column in the schema. The column values stage takes these and not the consumer's Hash: they
  # say which source column feeds a target column, how the values of the file are changed on the way, and the column
  # of the target table it fills. {MappedColumns} makes them from the consumer's Hash.
  #   source_column_name  String                  the source column the values are read from
  #   value_mapping  Hash{String => Object}  the value in the file (a text) => the value to load; empty when there is
  #                                          none
  #   target_column  TargetColumn            the column of the target table, which gives its type and limits
  ResolvedMappedColumn = Data.define(:source_column_name, :value_mapping, :target_column)
end
