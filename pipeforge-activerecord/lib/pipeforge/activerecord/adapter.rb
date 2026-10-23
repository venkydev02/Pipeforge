# frozen_string_literal: true

module Pipeforge
  # The target adapter for ActiveRecord (ADR-16, ADR-20). It reads the structure of a table and
  # of the application model that uses it, and nothing else: no row of the table is read.
  #
  # The target is named by its table. The adapter finds the application model whose table it
  # is among the models that are loaded; it never loads any itself, so loading them, and how, is
  # entirely the consumer's choice. A table
  # with no loaded model cannot be used. When a model has subclasses on the same table
  # (single table inheritance) the base class is used; when several unrelated models share the
  # table, the one with the first class name is used, and its name is in the schema.
  #
  # Only the columns that can be given a source column are in the schema. The primary key (filled
  # by the database), the columns the model ignores and the generated columns are left out, so
  # the rest of the engine never hears of them.
  #
  # @example
  #   schema = Pipeforge::ActiveRecordAdapter.new.schema(target_table: "users")
  #   schema.columns.map(&:name)  # => ["id", "email", "company_id"]
  class ActiveRecordAdapter
    # The column types whose size is a number of characters; for the others it is a number of bytes.
    TEXT_TYPES = %w[string text].freeze

    # @param target_table [String] the table to read
    # @return [TargetSchema]
    # @raise [TargetSchemaError] the table does not exist (+target_table_not_found+), or no
    #   application model uses it (+active_record_model_not_found+)
    def schema(target_table:)
      reject_missing_table(target_table: target_table)
      model = find_model(target_table: target_table)

      TargetSchema.new(table_name: target_table, model: model.name, columns: build_columns(model: model))
    end

    private

    def reject_missing_table(target_table:)
      table_exists = ActiveRecord::Base.with_connection do |connection|
        connection.data_source_exists?(target_table)
      end
      return if table_exists

      raise TargetSchemaError.single(
        code: :target_table_not_found,
        message: "table #{target_table} does not exist in the database",
        table: target_table
      )
    end

    # The application model of the table, among the models that are loaded; the base class when
    # there is single table inheritance.
    def find_model(target_table:)
      candidates = ActiveRecord::Base.descendants.select do |model|
        !model.abstract_class? && model.table_name == target_table
      end
      base_models = candidates.reject { |model| candidates.include?(model.superclass) }

      if base_models.empty?
        raise TargetSchemaError.single(
          code: :active_record_model_not_found,
          message: "no loaded model uses the table #{target_table}; the model must be loaded " \
                   "before the schema is read",
          table: target_table
        )
      end

      base_models.min_by { |model| model.name.to_s }
    end

    def build_columns(model:)
      database_columns = model.with_connection { |connection| connection.columns(model.table_name) }
      foreign_keys = foreign_keys_of(model: model)
      primary_keys = Array(model.primary_key)
      ignored_names = model.ignored_columns.map(&:to_s)
      target_columns = []

      database_columns.each do |database_column|
        next unless writable?(database_column: database_column, primary_keys: primary_keys, ignored_names: ignored_names)

        target_columns << build_column(database_column: database_column, foreign_key: foreign_keys[database_column.name])
      end

      target_columns
    end

    # Whether the column can be given a source column: it is not filled by the database (the
    # primary key), not ignored by the model and not generated (D10).
    def writable?(database_column:, primary_keys:, ignored_names:)
      return false if primary_keys.include?(database_column.name)
      return false if ignored_names.include?(database_column.name)

      !database_column.virtual?
    end

    def build_column(database_column:, foreign_key:)
      type = database_column.type.to_s
      text_type = TEXT_TYPES.include?(type)

      TargetColumn.new(
        name: database_column.name,
        type: type,
        sql_type: database_column.sql_type,
        limit: text_type ? nil : database_column.limit,
        max_length: text_type ? database_column.limit : nil,
        precision: database_column.precision,
        scale: database_column.scale,
        nullable: database_column.null,
        default: database_column.default,
        foreign_key: foreign_key
      )
    end

    # The foreign key columns of the model, by column name. A polymorphic association and a
    # composite key are left out: they are plain columns for now.
    def foreign_keys_of(model:)
      foreign_keys = {}

      model.reflect_on_all_associations(:belongs_to).each do |reflection|
        next if reflection.polymorphic?
        next unless reflection.foreign_key.is_a?(String)

        foreign_keys[reflection.foreign_key] = ForeignKey.new(
          association: reflection.name.to_s,
          parent_table: reflection.klass.table_name,
          required: parent_required?(model: model, reflection: reflection)
        )
      end

      foreign_keys
    end

    # A parent is required unless the association says optional: true; without that option the
    # model's own setting decides (Rails turns it on for new applications).
    def parent_required?(model:, reflection:)
      return !reflection.options[:optional] if reflection.options.key?(:optional)

      model.belongs_to_required_by_default ? true : false
    end
  end
end
