# frozen_string_literal: true

module Pipeforge
  # The structure of the target table, as a target adapter reports it (P2 in protocols.md).
  # It holds metadata only: no rows, counts or cell values.
  #
  # @example
  #   schema = Pipeforge::TargetSchema.new(table_name: "users", model: "User", columns: columns)
  #   schema.columns.map(&:name)  # => ["id", "email", "company_id"]
  TargetSchema = Data.define(:table_name, :model, :columns)

  # One column of the target table that can be given a source column. A column the engine would
  # never load into (the primary key, an ignored column, a generated column) is not in the
  # schema at all; the adapter leaves it out.
  #   type                the type name the value stage checks against (integer, string, ...)
  #   sql_type            the type as the database writes it
  #   limit, max_length, precision, scale   the size information that goes with the type
  #   foreign_key         a ForeignKey when the column points to a row of another table, else nil
  TargetColumn = Data.define(
    :name, :type, :sql_type, :limit, :max_length, :precision, :scale, :nullable, :default, :foreign_key
  )

  # A column that points to a row of another table.
  #   association   the name of the association (company)
  #   parent_table  the table it points to (companies)
  #   required      whether a parent row must exist
  ForeignKey = Data.define(:association, :parent_table, :required)
end
