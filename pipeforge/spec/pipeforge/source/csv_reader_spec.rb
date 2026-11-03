# frozen_string_literal: true

RSpec.describe Pipeforge::Source::CsvReader do
  subject(:reader) { described_class.new(source_io: source_io) }

  let(:source_io) { reusable_csv_io(csv) }
  let(:csv) { "A,B\n1,2\n3,4\n5,6\n" }
  let(:settings) { {execution: {chunk_size: chunk_size}} }

  # The reader takes its chunk size from Configuration.
  before { use_settings(settings) }
  let(:chunk_size) { 2000 }

  # Reads the whole file and returns the chunks as arrays of rows.
  def read_chunks
    [].tap { |chunks| reader.each_chunk { |rows| chunks << rows } }
  end

  # Reads the file with the given offset, chunk size or columns and returns the chunks.
  def read_chunks_with(**options)
    [].tap { |chunks| reader.each_chunk(**options) { |rows| chunks << rows } }
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
      let(:chunk_size) { 2 }

      it "yields chunks of at most that many rows" do
        expect(read_chunks.map(&:size)).to eq([2, 1])
      end
    end

    context "with an offset and chunks of two rows" do
      let(:chunk_size) { 2 }
      let(:csv) { "A\n1\n2\n3\n4\n5\n" }

      it "drops that many rows from the start of the file, and the chunks are cut after that" do
        expect(read_chunks_with(offset: 1)).to eq([[{"A" => "2"}, {"A" => "3"}], [{"A" => "4"}, {"A" => "5"}]])
      end

      it "does not yield a chunk that holds only dropped rows" do
        expect(read_chunks_with(offset: 2)).to eq([[{"A" => "3"}, {"A" => "4"}], [{"A" => "5"}]])
      end

      it "yields nothing when the offset is past the end of the file" do
        expect(read_chunks_with(offset: 9)).to eq([])
      end
    end

    context "with the chunk size given to the call" do
      let(:csv) { "A\n1\n2\n3\n4\n5\n" }

      it "yields chunks of at most that many rows" do
        expect(read_chunks_with(chunk_size: 3)).to eq(
          [[{"A" => "1"}, {"A" => "2"}, {"A" => "3"}], [{"A" => "4"}, {"A" => "5"}]]
        )
      end

      context "when the settings give another chunk size" do
        let(:chunk_size) { 2 }

        it "uses the one given to the call" do
          expect(read_chunks_with(chunk_size: 4).map(&:size)).to eq([4, 1])
        end

        it "uses the one of the settings when none is given" do
          expect(read_chunks.map(&:size)).to eq([2, 2, 1])
        end
      end

      it "yields one row at a time for a chunk size of 1" do
        expect(read_chunks_with(chunk_size: 1).map(&:size)).to eq([1, 1, 1, 1, 1])
      end

      it "cuts the chunks after the offset" do
        expect(read_chunks_with(offset: 1, chunk_size: 3)).to eq(
          [[{"A" => "2"}, {"A" => "3"}, {"A" => "4"}], [{"A" => "5"}]]
        )
      end

      it "returns the number of rows read, the dropped ones included, whatever the chunk size" do
        expect(reader.each_chunk(offset: 2, chunk_size: 2) { |_rows| }).to eq(5)
      end
    end

    context "with columns" do
      let(:csv) { "A,B,C\n1,2,3\n4,,6\n" }

      it "gives only those columns in each row" do
        expect(read_chunks_with(columns: %w[A C])).to eq([[{"A" => "1", "C" => "3"}, {"A" => "4", "C" => "6"}]])
      end

      it "still reads an empty cell of a requested column as nil" do
        expect(read_chunks_with(columns: %w[B]).flatten).to eq([{"B" => "2"}, {"B" => nil}])
      end

      context "when a row is empty in the requested columns only" do
        let(:csv) { "A,B\n,x\n1,y\n" }

        it "keeps the row, as without columns" do
          expect(read_chunks_with(columns: %w[A]).flatten).to eq([{"A" => nil}, {"A" => "1"}])
        end

        it "counts the row" do
          expect(reader.each_chunk(columns: %w[A]) { |_rows| }).to eq(2)
        end
      end

      context "when a row has more cells than the header" do
        let(:csv) { "A,B\n1,2,3\n" }

        it "still stops with source_row_too_long" do
          expect { read_chunks_with(columns: %w[A]) }.to raise_error(Pipeforge::Source::MalformedSourceError) do |error|
            expect(error.codes).to eq([:source_row_too_long])
          end
        end
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
      let(:chunk_size) { 2 }

      it "counts the rows of every chunk, not only the last" do
        expect(read_row_count).to eq(3)
      end
    end
  end

  describe "#each_row" do
    # Reads the whole file and returns the rows, one by one.
    def read_rows
      [].tap { |rows| reader.each_row { |row| rows << row } }
    end

    it "raises ArgumentError when it is called without a block" do
      expect { reader.each_row }.to raise_error(ArgumentError, /needs a block/)
    end

    it "yields each row as a hash of header to text, in file order" do
      expect(read_rows).to eq([{"A" => "1", "B" => "2"}, {"A" => "3", "B" => "4"}, {"A" => "5", "B" => "6"}])
    end

    it "returns the number of rows read" do
      expect(reader.each_row { |_row| }).to eq(3)
    end

    it "does not depend on the chunk size of the settings" do
      use_settings(execution: {chunk_size: 1})

      expect(read_rows.size).to eq(3)
    end

    context "with empty cells" do
      let(:csv) { "A,B\n1,\n , 4\n" }

      it "gives nil for a cell that is empty or only whitespace, and trims the others" do
        expect(read_rows).to eq([{"A" => "1", "B" => nil}, {"A" => nil, "B" => "4"}])
      end
    end

    context "with blank lines and rows with only empty cells" do
      let(:csv) { "A,B\n1,2\n\n,\n3,4\n" }

      it "does not yield them, and does not count them" do
        expect(read_rows).to eq([{"A" => "1", "B" => "2"}, {"A" => "3", "B" => "4"}])
        expect(reader.each_row { |_row| }).to eq(2)
      end
    end

    context "with a file that has only a header" do
      let(:csv) { "A,B\n" }

      it "yields nothing and returns zero" do
        expect(reader.each_row { |_row| }).to eq(0)
      end
    end

    context "with a file that has no header" do
      let(:csv) { "" }

      it "raises source_empty and yields nothing" do
        expect { reader.each_row { |_row| } }.to raise_error(Pipeforge::Source::EmptySourceError) do |error|
          expect(error.codes).to eq([:source_empty])
        end
      end
    end

    context "with a header that has a blank cell" do
      let(:csv) { "A,,C\n1,2,3\n" }

      it "raises source_header_blank before any row is yielded" do
        yielded = []

        expect { reader.each_row { |row| yielded << row } }.to raise_error(Pipeforge::Source::InvalidHeaderError)
        expect(yielded).to eq([])
      end
    end

    context "with a row that has more cells than the header" do
      let(:csv) { "A,B\n1,2\n1,2,3\n" }

      it "raises source_row_too_long, after the rows before it" do
        yielded = []

        expect { reader.each_row { |row| yielded << row } }.to raise_error(Pipeforge::Source::MalformedSourceError) do |error|
          expect(error.codes).to eq([:source_row_too_long])
        end
        expect(yielded.size).to eq(1)
      end
    end

    context "with a row that cannot be parsed" do
      let(:csv) { "A,B\n1,\"2\n" }

      it "raises malformed_row" do
        expect { reader.each_row { |_row| } }.to raise_error(Pipeforge::Source::MalformedSourceError) do |error|
          expect(error.codes).to eq([:malformed_row])
        end
      end
    end

    context "with a row that has fewer cells than the header" do
      let(:csv) { "A,B,C\n1,2\n" }

      it "fills the missing cells with nil" do
        expect(read_rows).to eq([{"A" => "1", "B" => "2", "C" => nil}])
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
