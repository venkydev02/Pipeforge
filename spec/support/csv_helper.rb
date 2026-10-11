# frozen_string_literal: true

# Writes CSV text to a temporary file and returns its path. The file is removed after the
# example, so a spec only states the text it needs.
#
#   let(:path) { csv_file("A,B\n1,2\n") }
module CsvHelper
  def csv_file(text)
    file = Tempfile.new(["source", ".csv"])
    file.write(text)
    file.flush
    csv_files << file
    file.path
  end

  def csv_files
    @csv_files ||= []
  end
end

RSpec.configure do |config|
  config.include CsvHelper
  config.after { csv_files.each(&:close!) }
end
