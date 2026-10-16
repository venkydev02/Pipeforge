# frozen_string_literal: true

require "stringio"

# Writes text to a temporary file and returns its path. The file is removed after the example,
# so a spec only states the text it needs.
#
#   let(:source_io) { csv_io("A,B\n1,2\n") }
#   let(:config_path) { yaml_file("engine:\n  execution:\n    batch_size: 10\n") }
module TempFileHelper
  # An in-memory source with the same methods as a file (read, rewind, seek).
  def csv_io(text)
    StringIO.new(text)
  end

  def csv_file(text)
    temp_file(text: text, extension: ".csv")
  end

  def yaml_file(text)
    temp_file(text: text, extension: ".yml")
  end

  private

  def temp_file(text:, extension:)
    file = Tempfile.new(["spec", extension])
    file.write(text)
    file.flush
    temp_files << file
    file.path
  end

  def temp_files
    @temp_files ||= []
  end
end

RSpec.configure do |config|
  config.include TempFileHelper
  config.after { temp_files.each(&:close!) }
end
