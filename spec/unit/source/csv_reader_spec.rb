# frozen_string_literal: true

RSpec.describe Pipeforge::Source::CsvReader do
  subject(:reader) { described_class.new(source_io: source_io) }

  let(:source_io) { reusable_csv_io(csv) }
  let(:yielded_chunks) { [] }
  let(:yielded_rows) { [] }

  def read_chunks(**options)
    reader.each_chunk(**options) { |rows| yielded_chunks << rows }
    yielded_chunks
  end

  def read_rows
    reader.each_row { |row| yielded_rows << row }
    yielded_rows
  end

  # The entries of the error of the given class, cut to the code and the given fields.
  def raised_entries(error_class, *fields)
    yield
    nil
  rescue error_class => error
    error.errors.map { |entry| entry.slice(:code, *fields) }
  end

  def row_of_a(text)
    {"A" => text}
  end

  describe ".new" do
    context "when source_io is a ReusableIO" do
      let(:csv) { "A,B\n1,2\n" }

      # contract only
      it "gives a CsvReader" do
        expect(reader).to be_a(described_class)
      end
    end

    describe "collaboration with the real ReusableIO" do
      let(:csv) { "A,B\n1,2\n" }
      let(:source_io_methods) { %i[gets read rewind eof? external_encoding] }

      it "makes no call on the source IO" do
        source_io_methods.each { |method_name| allow(source_io).to receive(method_name).and_call_original }

        reader

        source_io_methods.each { |method_name| expect(source_io).not_to have_received(method_name) }
      end
    end
  end

  describe "#headers" do
    describe "the names of a usable header" do
      context "when the header is A,B and there are three data rows" do
        let(:csv) { "A,B\n1,2\n3,4\n5,6\n" }

        # contract only
        it "gives an Array of Strings" do
          expect(reader.headers).to all(be_a(String))
        end

        it "gives the names in file order" do
          expect(reader.headers).to eq(%w[A B])
        end
      end

      context "when the file is only the header First Name,Last Name" do
        let(:csv) { "First Name,Last Name\n" }

        it "gives the two names" do
          expect(reader.headers).to eq(["First Name", "Last Name"])
        end
      end

      context "when the names have spaces around them" do
        let(:csv) { " A , B \n1,2\n" }

        it "trims the names" do
          expect(reader.headers).to eq(%w[A B])
        end
      end

      context "when a quoted name holds a comma" do
        let(:csv) { "\"Last, First\",B\n1,2\n" }

        it "keeps the name whole" do
          expect(reader.headers).to eq(["Last, First", "B"])
        end
      end
    end

    describe "a file or a header that cannot be used" do
      context "when the file is empty" do
        let(:csv) { "" }

        it "raises Source::Error with source_empty" do
          expect(raised_entries(Pipeforge::Source::Error) { reader.headers }).to eq([{code: :source_empty}])
        end
      end

      context "when the first line is blank and the header is on the second line" do
        let(:csv) { "\nA,B\n1,2\n" }

        it "raises Source::Error with source_empty" do
          expect(raised_entries(Pipeforge::Source::Error) { reader.headers }).to eq([{code: :source_empty}])
        end
      end

      context "when one header cell is blank" do
        let(:csv) { "A,,C\n1,2,3\n" }

        it "raises Source::Error with source_header_blank at position 2" do
          entries = raised_entries(Pipeforge::Source::Error, :position) { reader.headers }

          expect(entries).to eq([{code: :source_header_blank, position: 2}])
        end
      end

      context "when two header cells are blank" do
        let(:csv) { "A,,\n1,2,3\n" }

        it "raises Source::Error with source_header_blank at positions 2 and 3 and no repeated name" do
          entries = raised_entries(Pipeforge::Source::Error, :position) { reader.headers }

          expect(entries).to eq([{code: :source_header_blank, position: 2}, {code: :source_header_blank, position: 3}])
        end
      end

      context "when the name A appears twice" do
        let(:csv) { "A,A,B\n1,2,3\n" }

        it "raises Source::Error with one source_header_duplicated for A" do
          entries = raised_entries(Pipeforge::Source::Error, :source_column_name) { reader.headers }

          expect(entries).to eq([{code: :source_header_duplicated, source_column_name: "A"}])
        end
      end

      context "when a header cell is blank and a name appears twice" do
        let(:csv) { "A,A,\n1,2,3\n" }

        it "raises one Source::Error with the blank cell first and then the repeated name" do
          entries = raised_entries(Pipeforge::Source::Error, :position, :source_column_name) { reader.headers }

          expect(entries).to eq([
            {code: :source_header_blank, position: 3},
            {code: :source_header_duplicated, source_column_name: "A"}
          ])
        end
      end

      context "when the first data row cannot be parsed" do
        let(:csv_with_an_unclosed_quote_in_the_first_data_row) { "A,B\n\"1,2\n" }
        let(:csv) { csv_with_an_unclosed_quote_in_the_first_data_row }

        it "raises Source::Error with malformed_row at line 2" do
          entries = raised_entries(Pipeforge::Source::Error, :line) { reader.headers }

          expect(entries).to eq([{code: :malformed_row, line: 2}])
        end
      end

      context "when the first data row has more cells than the header" do
        let(:csv_whose_first_data_row_is_too_long) { "A,B\n1,2,3\n" }
        let(:csv) { csv_whose_first_data_row_is_too_long }

        it "raises Source::Error with source_row_too_long at line 2" do
          entries = raised_entries(Pipeforge::Source::Error, :line) { reader.headers }

          expect(entries).to eq([{code: :source_row_too_long, line: 2}])
        end

        context "and a blank line comes before that row" do
          let(:csv_whose_first_data_row_is_too_long_after_a_blank_line) { "A,B\n\n1,2,3\n" }
          let(:csv) { csv_whose_first_data_row_is_too_long_after_a_blank_line }

          it "raises Source::Error with source_row_too_long at line 3" do
            entries = raised_entries(Pipeforge::Source::Error, :line) { reader.headers }

            expect(entries).to eq([{code: :source_row_too_long, line: 3}])
          end
        end
      end
    end

    describe "the kept list of names" do
      context "when headers is called a second time" do
        let(:csv) { "A,B\n1,2\n" }

        it "gives the very same frozen list" do
          first_names = reader.headers

          expect(reader.headers).to equal(first_names)
        end

        it "gives a frozen list" do
          expect(reader.headers).to be_frozen
        end
      end

      context "when the rows have been read before" do
        let(:csv) { "A,B\n1,2\n3,4\n" }

        it "gives the names" do
          reader.each_row { |_row| }

          expect(reader.headers).to eq(%w[A B])
        end
      end
    end

    describe "collaboration with the real ReusableIO" do
      let(:csv) { "A,B\n1,2\n" }
      let(:calls_on_source_io) { [] }

      before do
        %i[gets read rewind eof? external_encoding].each do |method_name|
          allow(source_io).to receive(method_name).and_wrap_original do |original, *arguments|
            calls_on_source_io << method_name
            original.call(*arguments)
          end
        end
      end

      context "when headers is called twice" do
        it "reads from the source IO in the first call" do
          reader.headers

          expect(calls_on_source_io).not_to be_empty
        end

        it "makes no call on the source IO in the second call" do
          reader.headers

          expect { reader.headers }.not_to(change { calls_on_source_io.size })
        end
      end
    end
  end

  describe "#each_chunk" do
    describe "the block and the number given back" do
      context "when a block is given" do
        let(:csv) { "A,B\n1,2\n3,4\n" }

        # contract only
        it "yields Arrays of rows" do
          expect(read_chunks).to all(be_an(Array))
        end

        it "gives back an Integer" do
          expect(reader.each_chunk { |_rows| }).to be_an(Integer)
        end
      end

      context "when no block is given" do
        let(:csv) { "A,B\n1,2\n" }

        it "raises ArgumentError" do
          expect { reader.each_chunk }.to raise_error(ArgumentError)
        end
      end
    end

    describe "the rows" do
      context "when the header is A,B and there are three data rows" do
        let(:csv) { "A,B\n1,2\n3,4\n5,6\n" }
        let(:rows_of_the_file) do
          [{"A" => "1", "B" => "2"}, {"A" => "3", "B" => "4"}, {"A" => "5", "B" => "6"}]
        end

        it "yields the rows as Hashes of header => text, in file order" do
          expect(read_chunks).to eq([rows_of_the_file])
        end
      end

      context "when the cells are the numbers 007 and 1.50" do
        let(:csv) { "A,B\n007,1.50\n" }

        it "keeps them as the text written" do
          expect(read_chunks).to eq([[{"A" => "007", "B" => "1.50"}]])
        end
      end

      context "when a cell has spaces around it, a cell is empty and a cell holds only whitespace" do
        let(:csv) { "A,B,C\n 1 ,,  \n" }

        it "trims the text and gives the empty and the whitespace-only cell as nil" do
          expect(read_chunks).to eq([[{"A" => "1", "B" => nil, "C" => nil}]])
        end
      end

      context "when blank lines and rows of only empty cells are between data rows" do
        let(:csv) { "A,B\n1,2\n\n , \n,\n3,4\n" }

        it "does not yield them" do
          expect(read_chunks).to eq([[{"A" => "1", "B" => "2"}, {"A" => "3", "B" => "4"}]])
        end
      end

      context "when a row has fewer cells than the header" do
        let(:csv) { "A,B,C\n1\n" }

        it "gives the missing cells as nil" do
          expect(read_chunks).to eq([[{"A" => "1", "B" => nil, "C" => nil}]])
        end
      end

      context "when a quoted cell holds a newline" do
        let(:csv) { "A,B\n\"x\ny\",2\n" }

        it "keeps the newline in one cell" do
          expect(read_chunks).to eq([[{"A" => "x\ny", "B" => "2"}]])
        end
      end
    end

    describe "the chunks" do
      let(:csv) { "A\n1\n2\n3\n" }

      context "when chunk_size is 2 and there are three rows" do
        it "yields a chunk of 2 rows and a chunk of 1 row" do
          expect(read_chunks(chunk_size: 2)).to eq([[row_of_a("1"), row_of_a("2")], [row_of_a("3")]])
        end
      end

      context "when chunk_size is 1" do
        it "yields one row in each chunk" do
          expect(read_chunks(chunk_size: 1)).to eq([[row_of_a("1")], [row_of_a("2")], [row_of_a("3")]])
        end
      end

      context "when chunk_size is larger than the file" do
        it "yields one chunk with every row" do
          expect(read_chunks(chunk_size: 10)).to eq([[row_of_a("1"), row_of_a("2"), row_of_a("3")]])
        end
      end
    end

    describe "offset" do
      let(:csv) { "A\n1\n2\n3\n4\n5\n" }

      context "when offset is 1 and chunk_size is 2" do
        it "drops the first row and cuts the chunks after it" do
          expect(read_chunks(offset: 1, chunk_size: 2)).to eq([
            [row_of_a("2"), row_of_a("3")],
            [row_of_a("4"), row_of_a("5")]
          ])
        end
      end

      context "when offset is 2 and chunk_size is 2" do
        it "yields no chunk of only dropped rows" do
          expect(read_chunks(offset: 2, chunk_size: 2)).to eq([[row_of_a("3"), row_of_a("4")], [row_of_a("5")]])
        end
      end

      context "when offset is past the end of the file" do
        it "yields nothing" do
          expect(read_chunks(offset: 9, chunk_size: 2)).to eq([])
        end
      end
    end

    describe "columns" do
      context "when columns are A and C of a file with A,B,C" do
        let(:csv) { "A,B,C\n1,2,3\n4,5,6\n" }

        it "gives each row only those two keys" do
          expect(read_chunks(columns: %w[A C])).to eq([[{"A" => "1", "C" => "3"}, {"A" => "4", "C" => "6"}]])
        end
      end

      context "when a requested column has an empty cell" do
        let(:csv) { "A,B\n1,\n" }

        it "gives nil for the cell" do
          expect(read_chunks(columns: %w[B])).to eq([[{"B" => nil}]])
        end
      end

      context "when a row is empty in the requested columns only" do
        let(:csv) { "A,B,C\n1,,3\n" }

        it "yields the row" do
          expect(read_chunks(columns: %w[B])).to eq([[{"B" => nil}]])
        end

        it "counts the row" do
          expect(reader.each_chunk(columns: %w[B]) { |_rows| }).to eq(1)
        end
      end

      context "when a row has more cells than the header" do
        let(:csv_with_a_too_long_row_after_a_good_row) { "A,B,C\n1,2,3\n4,5,6,7\n" }
        let(:csv) { csv_with_a_too_long_row_after_a_good_row }

        it "raises Source::Error with source_row_too_long at line 3" do
          entries = raised_entries(Pipeforge::Source::Error, :line) { read_chunks(columns: %w[A]) }

          expect(entries).to eq([{code: :source_row_too_long, line: 3}])
        end
      end
    end

    describe "the number of data rows read" do
      context "when there are five rows, offset is 2 and chunk_size is 2" do
        let(:csv) { "A\n1\n2\n3\n4\n5\n" }

        it "gives 5, the dropped rows included" do
          expect(reader.each_chunk(offset: 2, chunk_size: 2) { |_rows| }).to eq(5)
        end
      end

      context "when there are a blank line and a row of only empty cells" do
        let(:csv) { "A,B\n1,2\n\n , \n3,4\n" }

        it "gives 2, with neither of them and not the header" do
          expect(reader.each_chunk { |_rows| }).to eq(2)
        end
      end

      context "when the file is only a header" do
        let(:csv) { "A,B\n" }

        it "gives 0" do
          expect(reader.each_chunk { |_rows| }).to eq(0)
        end

        it "yields nothing" do
          expect(read_chunks).to eq([])
        end
      end

      context "when chunk_size is smaller than the file" do
        let(:csv) { "A\n1\n2\n3\n4\n5\n" }

        it "gives the rows of every chunk" do
          expect(reader.each_chunk(chunk_size: 2) { |_rows| }).to eq(5)
        end
      end
    end

    describe "a file or a row that cannot be used" do
      context "when the file is empty" do
        let(:csv) { "" }

        it "raises Source::Error with source_empty" do
          expect(raised_entries(Pipeforge::Source::Error) { read_chunks }).to eq([{code: :source_empty}])
        end

        it "yields nothing" do
          raised_entries(Pipeforge::Source::Error) { read_chunks }

          expect(yielded_chunks).to eq([])
        end
      end

      context "when a header cell is blank" do
        let(:csv) { "A,,C\n1,2,3\n" }

        it "raises Source::Error with source_header_blank at position 2" do
          entries = raised_entries(Pipeforge::Source::Error, :position) { read_chunks }

          expect(entries).to eq([{code: :source_header_blank, position: 2}])
        end

        it "yields nothing" do
          raised_entries(Pipeforge::Source::Error) { read_chunks }

          expect(yielded_chunks).to eq([])
        end
      end

      context "when a row has more cells than the header" do
        let(:csv_with_a_too_long_second_row) { "A,B\n1,2\n3,4,5\n" }
        let(:csv) { csv_with_a_too_long_second_row }

        it "raises Source::Error with source_row_too_long at the line of the row" do
          entries = raised_entries(Pipeforge::Source::Error, :line) { read_chunks }

          expect(entries).to eq([{code: :source_row_too_long, line: 3}])
        end
      end

      context "when the extra cell of a row is empty" do
        let(:csv_with_a_row_whose_extra_cell_is_empty) { "A,B\n1,2\n3,4,\n" }
        let(:csv) { csv_with_a_row_whose_extra_cell_is_empty }

        it "raises Source::Error with source_row_too_long at the line of the row" do
          entries = raised_entries(Pipeforge::Source::Error, :line) { read_chunks }

          expect(entries).to eq([{code: :source_row_too_long, line: 3}])
        end
      end

      context "when a too long row follows a quoted cell that holds a newline" do
        let(:csv_with_a_too_long_row_after_a_multiline_cell) { "A,B\n\"x\ny\",2\n3,4,5\n" }
        let(:csv) { csv_with_a_too_long_row_after_a_multiline_cell }

        it "raises Source::Error with source_row_too_long at the physical line of the row" do
          entries = raised_entries(Pipeforge::Source::Error, :line) { read_chunks }

          expect(entries).to eq([{code: :source_row_too_long, line: 4}])
        end
      end

      context "when a row cannot be parsed" do
        let(:csv_with_an_unclosed_quote_in_the_second_row) { "A,B\n1,2\n\"3,4\n" }
        let(:csv) { csv_with_an_unclosed_quote_in_the_second_row }

        it "raises Source::Error with malformed_row at the line where the row starts" do
          entries = raised_entries(Pipeforge::Source::Error, :line) { read_chunks }

          expect(entries).to eq([{code: :malformed_row, line: 3}])
        end
      end

      context "when a bad row comes after rows that fill a whole chunk" do
        let(:csv_with_a_too_long_third_row) { "A\n1\n2\n3,4\n" }
        let(:csv) { csv_with_a_too_long_third_row }

        it "yields the chunk before the bad row and then raises source_row_too_long" do
          entries = raised_entries(Pipeforge::Source::Error, :line) { read_chunks(chunk_size: 2) }

          expect([yielded_chunks, entries]).to eq([[[row_of_a("1"), row_of_a("2")]], [{code: :source_row_too_long, line: 4}]])
        end
      end
    end

    describe "reading again" do
      let(:csv) { "A\n1\n2\n3\n" }

      context "when the file is read twice" do
        it "yields the same chunks each time" do
          first_read = [].tap { |chunks| reader.each_chunk(chunk_size: 2) { |rows| chunks << rows } }
          second_read = [].tap { |chunks| reader.each_chunk(chunk_size: 2) { |rows| chunks << rows } }

          expect(second_read).to eq(first_read)
        end

        it "gives back the same number each time" do
          first_count = reader.each_chunk(chunk_size: 2) { |_rows| }

          expect(reader.each_chunk(chunk_size: 2) { |_rows| }).to eq(first_count)
        end
      end

      context "when the names were read before with headers" do
        it "yields the rows from the first data row" do
          reader.headers

          expect(read_chunks).to eq([[row_of_a("1"), row_of_a("2"), row_of_a("3")]])
        end
      end
    end

    describe "collaboration with the real settings, source IO and gem" do
      context "when the setting execution.chunk_size is 2 and the file has three rows" do
        let(:csv) { "A\n1\n2\n3\n" }

        before { use_settings(execution: {chunk_size: 2}) }

        context "and no chunk_size is given" do
          it "cuts chunks of 2 rows" do
            expect(read_chunks).to eq([[row_of_a("1"), row_of_a("2")], [row_of_a("3")]])
          end
        end

        context "and chunk_size is 1" do
          before { allow(Pipeforge::Configuration).to receive(:execution).and_call_original }

          it "cuts chunks of 1 row" do
            expect(read_chunks(chunk_size: 1)).to eq([[row_of_a("1")], [row_of_a("2")], [row_of_a("3")]])
          end

          it "does not ask the settings" do
            read_chunks(chunk_size: 1)

            expect(Pipeforge::Configuration).not_to have_received(:execution)
          end
        end
      end

      context "when the file has a header, padded cells, a blank line, an all-empty row and a short row" do
        let(:csv_with_padded_blank_empty_and_short_rows) { "A,B,C\n 1 ,x, \n\n , ,\n2\n3,y,z\n" }
        let(:csv) { csv_with_padded_blank_empty_and_short_rows }
        let(:chunks_of_the_file) do
          [
            [{"A" => "1", "B" => "x", "C" => nil}, {"A" => "2", "B" => nil, "C" => nil}],
            [{"A" => "3", "B" => "y", "C" => "z"}]
          ]
        end

        before { allow(SmarterCSV::Reader).to receive(:new).and_call_original }

        it "yields the whole list of chunks" do
          expect(read_chunks(chunk_size: 2)).to eq(chunks_of_the_file)
        end

        it "gives back 3" do
          expect(reader.each_chunk(chunk_size: 2) { |_rows| }).to eq(3)
        end

        it "reads the source IO through the gem with the options of the reader" do
          read_chunks(chunk_size: 2)

          expect(SmarterCSV::Reader).to have_received(:new).with(source_io, described_class::OPTIONS)
        end
      end
    end
  end

  describe "#each_row" do
    describe "the block and the rows" do
      context "when no block is given" do
        let(:csv) { "A,B\n1,2\n" }

        it "raises ArgumentError" do
          expect { reader.each_row }.to raise_error(ArgumentError)
        end
      end

      context "when a block is given and there are three data rows" do
        let(:csv) { "A,B\n1,2\n3,4\n5,6\n" }
        let(:rows_of_the_file) do
          [{"A" => "1", "B" => "2"}, {"A" => "3", "B" => "4"}, {"A" => "5", "B" => "6"}]
        end

        it "yields the rows as Hashes of header => text, in file order" do
          expect(read_rows).to eq(rows_of_the_file)
        end

        it "gives back 3" do
          expect(reader.each_row { |_row| }).to eq(3)
        end
      end
    end

    describe "the rows" do
      context "when a cell has spaces around it and a cell is empty" do
        let(:csv) { "A,B\n 1 ,\n" }

        it "trims the text and gives the empty cell as nil" do
          expect(read_rows).to eq([{"A" => "1", "B" => nil}])
        end
      end

      context "when blank lines and rows of only empty cells are between data rows" do
        let(:csv) { "A,B\n1,2\n\n , \n3,4\n" }

        it "does not yield them" do
          expect(read_rows).to eq([{"A" => "1", "B" => "2"}, {"A" => "3", "B" => "4"}])
        end

        it "does not count them" do
          expect(reader.each_row { |_row| }).to eq(2)
        end
      end

      context "when a row has fewer cells than the header" do
        let(:csv) { "A,B,C\n1\n" }

        it "gives the missing cells as nil" do
          expect(read_rows).to eq([{"A" => "1", "B" => nil, "C" => nil}])
        end
      end

      context "when the file is only a header" do
        let(:csv) { "A,B\n" }

        it "yields nothing" do
          expect(read_rows).to eq([])
        end

        it "gives back 0" do
          expect(reader.each_row { |_row| }).to eq(0)
        end
      end

      context "when the setting execution.chunk_size is 1" do
        let(:csv) { "A\n1\n2\n3\n" }

        before { use_settings(execution: {chunk_size: 1}) }

        it "yields the same rows" do
          expect(read_rows).to eq([row_of_a("1"), row_of_a("2"), row_of_a("3")])
        end

        it "gives back 3" do
          expect(reader.each_row { |_row| }).to eq(3)
        end
      end
    end

    describe "a file or a row that cannot be used" do
      context "when the file is empty" do
        let(:csv) { "" }

        it "raises Source::Error with source_empty" do
          expect(raised_entries(Pipeforge::Source::Error) { read_rows }).to eq([{code: :source_empty}])
        end

        it "yields nothing" do
          raised_entries(Pipeforge::Source::Error) { read_rows }

          expect(yielded_rows).to eq([])
        end
      end

      context "when a header cell is blank" do
        let(:csv) { "A,,C\n1,2,3\n" }

        it "raises Source::Error with source_header_blank at position 2" do
          entries = raised_entries(Pipeforge::Source::Error, :position) { read_rows }

          expect(entries).to eq([{code: :source_header_blank, position: 2}])
        end

        it "yields nothing" do
          raised_entries(Pipeforge::Source::Error) { read_rows }

          expect(yielded_rows).to eq([])
        end
      end

      context "when a row has more cells than the header, after a good row" do
        let(:csv_with_a_too_long_row_after_a_good_row) { "A\n1\n2,3\n" }
        let(:csv) { csv_with_a_too_long_row_after_a_good_row }

        it "yields the good row and then raises source_row_too_long at the line of the row" do
          entries = raised_entries(Pipeforge::Source::Error, :line) { read_rows }

          expect([yielded_rows, entries]).to eq([[row_of_a("1")], [{code: :source_row_too_long, line: 3}]])
        end
      end

      context "when a row cannot be parsed" do
        let(:csv_with_an_unclosed_quote_in_the_second_row) { "A,B\n1,2\n\"3,4\n" }
        let(:csv) { csv_with_an_unclosed_quote_in_the_second_row }

        it "raises Source::Error with malformed_row at the line where the row starts" do
          entries = raised_entries(Pipeforge::Source::Error, :line) { read_rows }

          expect(entries).to eq([{code: :malformed_row, line: 3}])
        end
      end
    end

    describe "collaboration with the real source IO and gem" do
      let(:csv_with_padded_blank_empty_and_short_rows) { "A,B,C\n 1 ,x, \n\n , ,\n2\n3,y,z\n" }
      let(:csv) { csv_with_padded_blank_empty_and_short_rows }
      let(:rows_of_the_file) do
        [
          {"A" => "1", "B" => "x", "C" => nil},
          {"A" => "2", "B" => nil, "C" => nil},
          {"A" => "3", "B" => "y", "C" => "z"}
        ]
      end

      before { allow(SmarterCSV::Reader).to receive(:new).and_call_original }

      context "when the file has a header, padded cells, a blank line, an all-empty row and a short row" do
        it "yields the whole list of rows" do
          expect(read_rows).to eq(rows_of_the_file)
        end

        it "gives back 3" do
          expect(reader.each_row { |_row| }).to eq(3)
        end

        it "reads the source IO through the gem with the options of the reader" do
          read_rows

          expect(SmarterCSV::Reader).to have_received(:new).with(source_io, described_class::OPTIONS)
        end
      end
    end
  end
end
