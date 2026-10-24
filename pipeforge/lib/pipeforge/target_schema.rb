# frozen_string_literal: true

module Pipeforge
  # The structure of the target table, as a target adapter reports it. It holds metadata only:
  # no rows, counts or cell values.
  #
  # @example
  #   schema = Pipeforge::TargetSchema.new(table_name: "users", model: "User", columns: columns)
  #   schema.columns.map(&:name)  # => ["id", "email", "company_id"]
  TargetSchema = Data.define(:table_name, :model, :columns)

  # One column of the target table that can be given a source column. A column the engine would
  # never load into (the primary key, an ignored column, a generated column) is not in the
  # schema at all; the adapter leaves it out.
  #   type                the type name the value stage checks against (integer, string, ...)
  #   sql_type            the type as the table writes it
  #   limit, max_length, precision, scale   the size information that goes with the type
  #   default             the value filled in when none is given, as the model sees it (a default
  #                       set in the model counts, and an enum shows its label)
  #   enum_values         nil, or for an enum column the label => stored value pairs the model
  #                       accepts ({"draft" => 0, "placed" => 1})
  #   required            whether a row cannot be loaded without a source column for this column.
  #                       The adapter decides, from whether the column refuses an empty value
  #                       and has no default (what the framework fills in by itself counts as
  #                       a default)
  #   foreign_key         a ForeignKey when the column points to a row of another table, else nil
  TargetColumn = Data.define(
    :name, :type, :sql_type, :limit, :max_length, :precision, :scale, :default, :enum_values,
    :required, :foreign_key
  )

  # A column that points to a row of another table.
  #   association   the name of the association (company)
  #   parent_table  the table it points to (companies)
  ForeignKey = Data.define(:association, :parent_table)
end
