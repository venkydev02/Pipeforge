# frozen_string_literal: true

# Builds target columns and schemas for specs, with the details a spec does not care about
# filled in.
#
#   build_target_column(name: "email", max_length: 255)
#   build_target_schema(columns: [build_target_column(name: "email")])
module TargetSchemaHelper
  def build_target_column(name:, **overrides)
    defaults = {
      type: "string", sql_type: "varchar", limit: nil, max_length: nil, precision: nil, scale: nil,
      default: nil, enum_values: nil, required: false, foreign_key: nil
    }

    Pipeforge::TargetColumn.new(name: name, **defaults.merge(overrides))
  end

  def build_target_schema(columns:, table_name: "users", model: "User")
    Pipeforge::TargetSchema.new(table_name: table_name, model: model, columns: columns)
  end

  def build_foreign_key(association:, parent_table:)
    Pipeforge::ForeignKey.new(association: association, parent_table: parent_table)
  end
end

RSpec.configure { |config| config.include TargetSchemaHelper }
