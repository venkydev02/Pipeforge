# frozen_string_literal: true

require "bigdecimal"
require "date"

# A model adapter for specs of the core, which has no adapter gem. It follows the same contract as a
# real one: +build_record+ returns an object that answers +valid?+, +load+, +errors+ and +attributes+,
# +preload_parents+ takes the records of a chunk, +transaction+ runs a block, and +cast_text+ gives the
# value for a text.
#
# The errors of a record come from the +errors_of+ lambda, which is given the attributes the record
# was built from. The +changes_on_validation+ lambda stands for the model's callbacks: it is given the
# attributes when +valid?+ runs, and what it returns is what +attributes+ answers afterwards. The
# +load_errors_of+ lambda is given the attributes of a record when it is written: the entries it returns
# are the database's refusal (the write fails and +errors+ holds them), and an empty list is a write that
# works. The +casts+ lambda stands for the cast of the model: by default a text is cast to itself, and
# {.reading} and {.lenient} build adapters that cast by the type of the column. The adapter remembers
# what it was asked, so a spec can check it: +events+ lists, in order, each +:valid+ and +:load+ of a record
# (with its attributes) and the +:transaction_begin+ and +:transaction_end+ of a run transaction.
#
#   adapter = FakeModelAdapter.new(errors_of: ->(attributes:) { [model_error] if attributes["email"] == "x" })
#   FakeModelAdapter.reading(types: {"age" => "integer"}).cast_text(column_name: "age", text: "abc")   # => nil
#   FakeModelAdapter.lenient(types: {"age" => "integer"}).cast_text(column_name: "age", text: "abc")   # => 0
class FakeModelAdapter
  # What ActiveRecord reads as false; it reads every other text as true.
  FALSE_WORDS = %w[0 f false off].freeze

  # The words a strict adapter reads as a boolean: it cannot read any other text.
  STRICT_FALSE_WORDS = %w[0 f false off n no].freeze
  STRICT_TRUE_WORDS = %w[1 t true on y yes].freeze

  # An adapter that reads a text only when it is a value of the type of its column, and cannot read
  # (casts to nil) any other text. It stands for an adapter that is strict, and lets a spec about the
  # counting and the lists use texts that do not fit.
  #
  # @param types [Hash{String => String}] column => type name; a column not listed is cast to its text
  def self.reading(types: {})
    new(casts: lambda do |column_name:, text:|
      case types.fetch(column_name, "string")
      when "integer" then Integer(text, 10, exception: false)
      when "float" then Float(text, exception: false)
      when "decimal" then BigDecimal(text, exception: false)
      when "boolean" then strict_boolean(text)
      when "date" then iso_date(text)
      when "uuid" then text if text.match?(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/)
      else text
      end
    end)
  end

  # An adapter that casts as ActiveRecord does: leniently, so +abc+ in an integer column is 0, +1,000+
  # is 1 and +no+ in a boolean column is true. A date it cannot read is nil.
  #
  # @param types [Hash{String => String}] column => type name; a column not listed is cast to its text
  # @param scales [Hash{String => Integer}] decimal column => its scale, to which a decimal is rounded
  def self.lenient(types: {}, scales: {})
    new(casts: lambda do |column_name:, text:|
      case types.fetch(column_name, "string")
      when "integer" then text.to_i
      when "float" then text.to_f
      when "decimal" then BigDecimal(text.to_r, 20).round(scales.fetch(column_name, 2))
      when "boolean" then !FALSE_WORDS.include?(text.downcase)
      when "date" then lenient_date(text)
      else text
      end
    end)
  end

  # true or false for a word a strict adapter reads, else nil.
  def self.strict_boolean(text)
    return true if STRICT_TRUE_WORDS.include?(text.downcase)

    false if STRICT_FALSE_WORDS.include?(text.downcase)
  end

  # A date written as YYYY-MM-DD that exists in the calendar, else nil.
  def self.iso_date(text)
    Date.iso8601(text) if text.match?(/\A\d{4}-\d{2}-\d{2}\z/)
  rescue Date::Error
    nil
  end

  # A date in any form Ruby's parser reads, else nil.
  def self.lenient_date(text)
    Date.parse(text)
  rescue Date::Error
    nil
  end

  # The record that +build_record+ returns.
  class FakeModelRecord
    attr_reader :attributes, :errors

    def initialize(attributes:, errors:, changes_on_validation:, load_errors:, events:)
      @attributes = attributes
      @errors = errors
      @changes_on_validation = changes_on_validation
      @load_errors = load_errors
      @events = events
    end

    def valid?
      @events << [:valid, @attributes]
      @attributes = @changes_on_validation.call(attributes: @attributes)

      @errors.empty?
    end

    # Stands for the write: true, or false with the configured database errors in +errors+.
    def load
      @events << [:load, @attributes]
      @errors = @load_errors

      @load_errors.empty?
    end
  end

  # @return [Array<Hash>] the attributes of every record built, in order
  attr_reader :built_attributes

  # @return [Array<Array>] the records given to each +preload_parents+ call, in order
  attr_reader :preload_calls

  # @return [Array<Hash>] the +rollback_at_end+ of each +transaction+ call, in order
  attr_reader :transaction_calls

  # @return [Array<Array>] what happened to the records and the run transaction, in order
  attr_reader :events

  def initialize(errors_of: ->(attributes:) { [] }, changes_on_validation: ->(attributes:) { attributes },
    load_errors_of: ->(attributes:) { [] }, casts: ->(column_name:, text:) { text })
    @errors_of = errors_of
    @changes_on_validation = changes_on_validation
    @load_errors_of = load_errors_of
    @casts = casts
    @built_attributes = []
    @preload_calls = []
    @transaction_calls = []
    @events = []
  end

  def build_record(attributes:)
    @built_attributes << attributes
    FakeModelRecord.new(
      attributes: attributes, errors: @errors_of.call(attributes: attributes),
      changes_on_validation: @changes_on_validation,
      load_errors: @load_errors_of.call(attributes: attributes), events: @events
    )
  end

  def preload_parents(records:)
    @preload_calls << records
  end

  # Stands for the run transaction: remembers +rollback_at_end+, yields and gives the block's result.
  def transaction(rollback_at_end:)
    @transaction_calls << {rollback_at_end: rollback_at_end}
    @events << [:transaction_begin]
    result = yield
    @events << [:transaction_end]

    result
  end

  # The value the adapter would load for a text; the +casts+ lambda decides, and by default it is the
  # text itself. A lambda that returns nil stands for an adapter that cannot read the text.
  def cast_text(column_name:, text:)
    @casts.call(column_name: column_name, text: text)
  end
end
