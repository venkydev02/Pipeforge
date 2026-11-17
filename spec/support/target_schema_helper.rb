# frozen_string_literal: true

# Builds target columns and schemas for specs, with the details a spec does not care about
# filled in.
#
#   build_target_column(name: "email", max_length: 255)
#   build_target_schema(columns: [build_target_column(name: "email")])
module TargetSchemaHelper
  def build_target_column(name:, **overrides)
    defaults = {
      type: "string", sql_type: "varchar", limit: nil, is_signed: nil, max_length: nil, precision: nil, scale: nil,
      default: nil, enum_labels: nil, required: false, foreign_key: nil
    }

    Pipeforge::TargetColumn.new(name: name, **defaults.merge(overrides))
  end

  def build_target_schema(columns:, table_name: "users", model_name: "User")
    Pipeforge::TargetSchema.new(table_name: table_name, model_name: model_name, columns: columns)
  end

  def build_foreign_key(association_name:, parent_table_name:)
    Pipeforge::ForeignKey.new(association_name: association_name, parent_table_name: parent_table_name)
  end
end

RSpec.configure { |config| config.include TargetSchemaHelper }
