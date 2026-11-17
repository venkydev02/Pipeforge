# frozen_string_literal: true

module Pipeforge
  # The structure of the target table, as a target reports it. It holds metadata only:
  # no rows, counts or cell values.
  #
  # @example
  #   schema = Pipeforge::TargetSchema.new(table_name: "users", model_name: "User", columns: columns)
  #   schema.columns.map(&:name)  # => ["id", "email", "company_id"]
  TargetSchema = Data.define(:table_name, :model_name, :columns)

  # One column of the target table that can be given a source column. A column the engine would
  # never load into (the primary key, an ignored column, a generated column) is not in the
  # schema at all; the adapter leaves it out.
  #   type                the type name the column values stage checks against (integer, string, ...)
  #   sql_type            the type as the table writes it
  #   limit, max_length, precision, scale   the size information that goes with the type
  #   is_signed           for an integer column, true when it holds negative numbers and false when it does not
  #                       (an unsigned integer); nil for every other column, which has no sign
  #   default             the value filled in when none is given, as the model sees it (a default
  #                       set in the model counts, and an enum shows its label)
  #   enum_labels         nil, or for an enum column the labels the model accepts (["draft", "placed"]), as
  #                       text; the values the database stores for them are not part of the schema
  #   required            whether a row cannot be loaded without a source column for this column.
  #                       The adapter decides, from whether the column refuses an empty value
  #                       and has no default (what the framework fills in by itself counts as
  #                       a default)
  #   foreign_key         a ForeignKey when the column points to a row of another table, else nil
  TargetColumn = Data.define(
    :name, :type, :sql_type, :limit, :is_signed, :max_length, :precision, :scale, :default, :enum_labels,
    :required, :foreign_key
  )

  # A column that points to a row of another table.
  #   association_name   the name of the association (company)
  #   parent_table_name  the table it points to (companies)
  ForeignKey = Data.define(:association_name, :parent_table_name)
end
