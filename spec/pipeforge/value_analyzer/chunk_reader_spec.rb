# frozen_string_literal: true

RSpec.describe Pipeforge::ValueAnalyzer::ChunkReader do
  subject(:reader) { described_class.new(path: path, config: config) }

  let(:path) { csv_file(csv) }
  let(:csv) { "A,B\n1,2\n3,4\n5,6\n" }
  let(:config) { build_configuration(execution: {batch_size: batch_size}) }
  let(:batch_size) { 2000 }

  # Reads the whole file and returns the chunks as arrays of rows.
  def read_chunks
    [].tap { |chunks| reader.each_chunk { |rows| chunks << rows } }
  end

  describe "#each_chunk" do
    it "yields rows as hashes of header to text" do
      expect(read_chunks).to eq([[{"A" => "1", "B" => "2"}, {"A" => "3", "B" => "4"}, {"A" => "5", "B" => "6"}]])
    end

    it "returns an Enumerator when it is called without a block" do
      expect(reader.each_chunk).to be_an(Enumerator)
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

    context "with a header cell that is blank and a row with an extra cell" do
      let(:csv) { "A,,C\n1,2,3,4\n" }

      it "gives them made-up names that cannot collide with a real column" do
        expect(read_chunks.flatten.first.keys).to eq(["A", "__unnamed_2", "C", :__unnamed_4])
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

  describe "#row_count" do
    it "is zero before the file is read" do
      expect(reader.row_count).to eq(0)
    end

    it "counts the data rows once the file is read" do
      read_chunks

      expect(reader.row_count).to eq(3)
    end

    context "with a blank line and an all-empty row" do
      let(:csv) { "A,B\n1,2\n\n,\n3,4\n" }

      it "does not count the rows that are dropped, nor the header" do
        read_chunks

        expect(reader.row_count).to eq(2)
      end
    end

    context "with only a header" do
      let(:csv) { "A,B\n" }

      it "is zero" do
        read_chunks

        expect(reader.row_count).to eq(0)
      end
    end
  end

  describe "#headers" do
    let(:csv) { " A , B \n1,2\n" }

    it "lists the column names in file order, trimmed" do
      read_chunks

      expect(reader.headers).to eq(%w[A B])
    end

    context "with only a header" do
      let(:csv) { "A,B\n" }

      it "is available when there are no data rows" do
        read_chunks

        expect(reader.headers).to eq(%w[A B])
      end
    end
  end
end
