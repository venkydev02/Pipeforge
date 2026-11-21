# frozen_string_literal: true

require "active_record"

# Reads the SQL statements that ActiveRecord sends to the database while a block runs, so an example can say "this
# sent one query on the companies table" or "this sent no query". ActiveRecord publishes each statement as the event
# "sql.active_record" (through ActiveSupport::Notifications), and the helper listens to it for the length of the block.
#
#   queries_on("companies") { target.preload_parents(records: model_records) }.size   # => 1
#   statement_names { model_record }.uniq - ["SCHEMA"]                               # => []
module SqlStatementsHelper
  # @param table [String] the name of a table
  # @yield the code whose statements are read
  # @return [Array<String>] the statements that name the table, in the order they were sent; the reads of the structure
  #   of a table (labelled "SCHEMA") are left out, because ActiveRecord keeps them and whether one is sent depends on
  #   what ran before
  def queries_on(table, &block)
    statements = []

    sql_payloads_during(&block).each do |payload|
      next if payload[:name] == "SCHEMA"

      statements << payload[:sql] if payload[:sql].include?(%("#{table}"))
    end

    statements
  end

  # @yield the code whose statements are read
  # @return [Array<String, nil>] the label ActiveRecord gave each statement the block sent ("SCHEMA" for a read of the
  #   structure of a table, "Company Load" for a read of rows), in the order they were sent
  def statement_names(&block)
    names = []

    sql_payloads_during(&block).each { |payload| names << payload[:name] }

    names
  end

  private

  # The details of each statement sent while the block runs.
  def sql_payloads_during(&block)
    payloads = []
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |_name, _start, _finish, _id, payload|
      payloads << payload
    end
    block.call

    payloads
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end
end

RSpec.configure do |config|
  config.include SqlStatementsHelper
end
