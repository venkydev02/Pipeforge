# frozen_string_literal: true

RSpec.describe Pipeforge::Source::CsvReader do
  subject(:reader) { described_class.new(source_io: source_io) }

  let(:source_io) { reusable_csv_io(csv) }
  let(:csv) { "A,B\n1,2\n3,4\n5,6\n" }
  let(:settings) { {execution: {batch_size: batch_size}} }

  # The reader takes its chunk size from Configuration.
  before { use_settings(settings) }
  let(:batch_size) { 2000 }

  # Reads the whole file and returns the chunks as arrays of rows.
  def read_chunks
    [].tap { |chunks| reader.each_chunk { |rows| chunks << rows } }
  end

  # Reads the whole file and returns the row count that each_chunk gives back.
  def read_row_count
    reader.each_chunk { |_rows| }
  end

  describe "#each_chunk" do
    it "raises ArgumentError when it is called without a block" do
      expect { reader.each_chunk }.to raise_error(ArgumentError, /needs a block/)
    end

    context "with a file that has only a header, called without a block" do
      let(:csv) { "A,B\n" }

      it "raises ArgumentError as well" do
        expect { reader.each_chunk }.to raise_error(ArgumentError, /needs a block/)
      end
    end

    it "yields rows as hashes of header to text" do
      expect(read_chunks).to eq([[{"A" => "1", "B" => "2"}, {"A" => "3", "B" => "4"}, {"A" => "5", "B" => "6"}]])
    end

    context "with a batch size smaller than the file" do
      let(:batch_size) { 2 }

      it "yields chunks of at most that many rows" do
        expect(read_chunks.map(&:size)).to eq([2, 1])
      end
    end

    context "with blank lines and rows whose cells are all empty" do
      let(:csv) { "A,B\n1,2\n\n,\n  ,  \n3,4\n" }

      it "drops them" do
        expect(read_chunks.flatten.size).to eq(2)
      end
    end

    context "with empty and padded cells" do
      let(:csv) { "A,B\n 1 ,\n  ,x\n" }

      it "trims the text and reads an empty or whitespace-only cell as nil" do
        expect(read_chunks.flatten).to eq([{"A" => "1", "B" => nil}, {"A" => nil, "B" => "x"}])
      end
    end

    context "with numbers" do
      let(:csv) { "A\n007\n1.50\n" }

      it "keeps them as written, as text" do
        expect(read_chunks.flatten.map { |row| row["A"] }).to eq(%w[007 1.50])
      end
    end

    context "with a header cell that is blank" do
      let(:csv) { "A,,C\n1,2,3\n" }

      it "raises before yielding any rows" do
        expect { read_chunks }.to raise_error(Pipeforge::Source::InvalidHeaderError) do |error|
          expect(error.errors.map { |entry| entry[:code] }).to eq([:source_header_blank])
        end
      end
    end

    context "with an empty file" do
      let(:csv) { "" }

      it "raises source_empty" do
        expect { read_chunks }.to raise_error(Pipeforge::Source::EmptySourceError)
      end
    end

    context "with a row that has more cells than the header" do
      let(:csv) { "A,B\n1,2\n3,4,5\n" }

      it "raises source_row_too_long, with the line of the row" do
        expect { read_chunks }.to raise_error(Pipeforge::Source::MalformedSourceError) do |error|
          expect(error.errors.map { |entry| entry.slice(:code, :line) }).to eq([{code: :source_row_too_long, line: 3}])
        end
      end
    end

    context "with a row whose extra cell is empty" do
      let(:csv) { "A,B\n1,2,\n" }

      it "raises source_row_too_long too" do
        expect { read_chunks }.to raise_error(Pipeforge::Source::MalformedSourceError) do |error|
          expect(error.errors.map { |entry| entry[:code] }).to eq([:source_row_too_long])
        end
      end
    end

    context "with a row that has fewer cells than the header" do
      let(:csv) { "A,B,C\n1,2\n" }

      it "fills the missing cells with nil" do
        expect(read_chunks.flatten).to eq([{"A" => "1", "B" => "2", "C" => nil}])
      end
    end

    context "when a row cannot be parsed" do
      let(:csv) { "A\n1\n\"never closed\n2\n" }

      it "raises our own error, naming the line where the row starts" do
        expect { read_chunks }.to raise_error(Pipeforge::Source::MalformedSourceError, /line 3/) do |error|
          expect(error.line).to eq(3)
        end
      end

      it "gives the code malformed_row, with the line" do
        expect { read_chunks }.to raise_error(Pipeforge::Source::MalformedSourceError) do |error|
          expect(error.errors.map { |entry| entry.slice(:code, :line) }).to eq([{code: :malformed_row, line: 3}])
        end
      end
    end
  end

  describe "the row count that #each_chunk returns" do
    it "is the number of data rows once the file is read" do
      expect(read_row_count).to eq(3)
    end

    context "with a blank line and an all-empty row" do
      let(:csv) { "A,B\n1,2\n\n,\n3,4\n" }

      it "does not count the rows that are dropped, nor the header" do
        expect(read_row_count).to eq(2)
      end
    end

    context "with only a header" do
      let(:csv) { "A,B\n" }

      it "is zero" do
        expect(read_row_count).to eq(0)
      end
    end

    context "with a batch size smaller than the file" do
      let(:batch_size) { 2 }

      it "counts the rows of every chunk, not only the last" do
        expect(read_row_count).to eq(3)
      end
    end
  end

  describe "#headers" do
    it "gives the column names in file order" do
      expect(reader.headers).to eq(%w[A B])
    end

    context "with only a header" do
      let(:csv) { "First Name,Last Name\n" }

      it "gives the names" do
        expect(reader.headers).to eq(["First Name", "Last Name"])
      end
    end

    context "with spaces around the names" do
      let(:csv) { " A , B \n1,2\n" }

      it "trims them" do
        expect(reader.headers).to eq(%w[A B])
      end
    end

    context "with a quoted name that holds a comma" do
      let(:csv) { "\"Last, First\",B\n1,2\n" }

      it "keeps the name whole" do
        expect(reader.headers).to eq(["Last, First", "B"])
      end
    end

    context "with a name that appears twice" do
      let(:csv) { "A,A,B\n1,2,3\n" }

      it "stops with source_header_duplicated and the name" do
        expect { reader.headers }.to raise_error(Pipeforge::Source::InvalidHeaderError) do |error|
          expect(error.errors.map { |entry| entry.slice(:code, :source_column) }).to eq(
            [{code: :source_header_duplicated, source_column: "A"}]
          )
        end
      end
    end

    context "with a blank header cell" do
      let(:csv) { "A,,C\n1,2,3\n" }

      it "stops with source_header_blank and the position of the cell" do
        expect { reader.headers }.to raise_error(Pipeforge::Source::InvalidHeaderError) do |error|
          expect(error.errors.map { |entry| entry.slice(:code, :position) }).to eq(
            [{code: :source_header_blank, position: 2}]
          )
        end
      end
    end

    context "with two blank cells" do
      let(:csv) { "A,,\n1,2,3\n" }

      it "reports each blank cell, and does not call the blank name a repeated name" do
        expect { reader.headers }.to raise_error(Pipeforge::Source::InvalidHeaderError) do |error|
          expect(error.codes).to eq(%i[source_header_blank source_header_blank])
        end
      end
    end

    context "with a blank cell and a repeated name" do
      let(:csv) { "A,A,\n1,2,3\n" }

      it "reports every mistake together" do
        expect { reader.headers }.to raise_error(Pipeforge::Source::InvalidHeaderError) do |error|
          expect(error.codes).to eq(%i[source_header_blank source_header_duplicated])
        end
      end
    end

    context "with an empty file" do
      let(:csv) { "" }

      it "stops with source_empty" do
        expect { reader.headers }.to raise_error(Pipeforge::Source::EmptySourceError) do |error|
          expect(error.codes).to eq([:source_empty])
        end
      end
    end

    context "with a first line that is blank" do
      let(:csv) { "\nA,B\n1,2\n" }

      it "stops with source_empty" do
        expect { reader.headers }.to raise_error(Pipeforge::Source::EmptySourceError)
      end
    end

    it "gives the same names when it is called again" do
      first_names = reader.headers

      expect(reader.headers).to equal(first_names)
    end

    it "keeps the names frozen, because they are shared" do
      expect(reader.headers).to be_frozen
    end

    it "does not read the file again once the names are known" do
      reader.headers
      source_io.rewind
      allow(source_io).to receive(:gets).and_call_original

      reader.headers

      expect(source_io).not_to have_received(:gets)
    end

    it "leaves the file ready to be read from the top" do
      reader.headers

      expect(read_chunks.first.size).to eq(3)
    end
  end

  describe "reading the file more than once" do
    it "yields the same rows each time" do
      first_rows = read_chunks.flatten

      expect(read_chunks.flatten).to eq(first_rows)
    end

    it "returns the same row count each time" do
      read_row_count

      expect(read_row_count).to eq(3)
    end

    it "gives the headers after the rows have been read" do
      read_chunks

      expect(reader.headers).to eq(%w[A B])
    end
  end
end
