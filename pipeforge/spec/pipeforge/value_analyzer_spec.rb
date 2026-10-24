# frozen_string_literal: true

require "json"

RSpec.describe Pipeforge::ValueAnalyzer do
  let(:settings) { {} }

  # The parts of the engine read their settings from Configuration; the example's settings.
  before { use_settings(settings) }

  # The result of an analysis that uses other settings than the example's own. Evaluate the
  # example's own result first: the settings stay replaced afterwards.
  def result_with(settings)
    use_settings(settings)
    described_class.call(source_reader: csv_reader(csv), mapped_columns: mapped_columns)
  end

  # One mapping value: the target column of a source column and the type of that column.
  def maps_to(source_column:, type:, **type_info)
    {source_column: source_column, type: type}.merge(type_info)
  end

  describe "#call" do
    subject(:result) { described_class.call(source_reader: source_reader, mapped_columns: mapped_columns) }

    let(:source_reader) { csv_reader(csv) }
    # Four data rows: a value spanning two lines, empty cells, a whitespace-only cell, a blank line.
    let(:csv) do
      <<~CSV
        Full Name,Age,Notes
        Alice,30,"first line
        second line"
        Bob,,
         ,25,hi

        Cara,x,
      CSV
    end
    let(:mapped_columns) do
      {
        "name" => maps_to(source_column: "Full Name", type: "string"),
        "age" => maps_to(source_column: "Age", type: "integer"),
        "notes" => maps_to(source_column: "Notes", type: "text")
      }
    end

    context "with a typical file" do
      let(:file) { File.open(csv_file(csv)) }
      let(:source_reader) { Pipeforge::Source::CsvReader.new(source_io: Pipeforge::Source::ReusableIO.new(io: file)) }

      it "names the source file" do
        expect(result.source_identifier).to eq(file.path)
      end

      it "counts the data rows, not the blank line" do
        expect(result.row_count).to eq(4)
      end

      it "has one summary per mapped column, keyed by target column, in the order of the mapping" do
        expect(result.columns.keys).to eq(%w[name age notes])
      end

      it "gives each summary its source column and the position of that column in the file" do
        expect(result.columns).to include(
          "name" => have_attributes(source_column: "Full Name", position: 1),
          "age" => have_attributes(source_column: "Age", position: 2),
          "notes" => have_attributes(source_column: "Notes", position: 3)
        )
      end

      it "counts empty and whitespace-only cells as empty" do
        expect(result.columns.transform_values(&:empty)).to eq("name" => 1, "age" => 1, "notes" => 2)
      end

      it "counts the non-empty values that fit the target type" do
        expect(result.columns["age"].type_compatibility).to eq(fits: 2, total: 3)
      end

      it "lists the values that fit, with their counts" do
        expect(result.columns["age"].distinct_values[:compatible].values)
          .to eq([{value: "30", count: 1}, {value: "25", count: 1}])
      end

      it "lists the values that do not fit, with their counts" do
        expect(result.columns["age"].distinct_values[:incompatible].values).to eq([{value: "x", count: 1}])
      end

      it "leaves empty values out of both lists" do
        notes = result.columns["notes"].distinct_values

        expect(notes[:compatible].values.map { |listed| listed[:value] }).to eq(["first line\nsecond line", "hi"])
        expect(notes[:incompatible].values).to be_empty
      end
    end

    context "when only some of the columns are mapped" do
      let(:mapped_columns) { {"age" => maps_to(source_column: "Age", type: "integer")} }

      it "measures only the mapped columns" do
        expect(result.columns.keys).to eq(["age"])
      end

      it "keeps the position the column has in the file" do
        expect(result.columns["age"].position).to eq(2)
      end
    end

    context "when the mapping lists the columns in another order than the file" do
      let(:mapped_columns) do
        {
          "notes" => maps_to(source_column: "Notes", type: "text"),
          "age" => maps_to(source_column: "Age", type: "integer"),
          "name" => maps_to(source_column: "Full Name", type: "string")
        }
      end

      it "returns the columns in the order of the mapping" do
        expect(result.columns.keys).to eq(%w[notes age name])
      end

      it "still gives each one the position of its source column in the file" do
        expect(result.columns.transform_values(&:position)).to eq("notes" => 3, "age" => 2, "name" => 1)
      end
    end

    context "when two target columns read the same source column" do
      let(:csv) { "Name\nAnn Lee\nBob\n" }
      let(:mapped_columns) do
        {
          "first_name" => maps_to(source_column: "Name", type: "string", max_length: 5),
          "full_name" => maps_to(source_column: "Name", type: "string", max_length: 50)
        }
      end

      it "measures the source column once for each of them" do
        expect(result.columns.transform_values(&:type_compatibility)).to eq(
          "first_name" => {fits: 1, total: 2}, "full_name" => {fits: 2, total: 2}
        )
      end

      it "gives both the same source column and position" do
        expect(result.columns.values).to all(have_attributes(source_column: "Name", position: 1))
      end

      it "counts the rows of the file once" do
        expect(result.row_count).to eq(2)
      end
    end

    context "when the mapping is empty" do
      let(:mapped_columns) { {} }

      it "measures no column" do
        expect(result.columns).to be_empty
      end

      it "still counts the rows" do
        expect(result.row_count).to eq(4)
      end
    end

    context "when the target type limits the length of the text" do
      let(:mapped_columns) { {"name" => maps_to(source_column: "Full Name", type: "string", max_length: 3)} }

      it "counts the values within the limit as fitting" do
        expect(result.columns["name"].type_compatibility).to eq(fits: 1, total: 3)
      end

      it "lists the values over the limit as not fitting" do
        expect(result.columns["name"].distinct_values[:incompatible].values)
          .to eq([{value: "Alice", count: 1}, {value: "Cara", count: 1}])
      end
    end

    context "when the target type has no fit rule yet" do
      let(:csv) { "Data\n{\"a\": 1}\nnot json\n" }
      let(:mapped_columns) { {"data" => maps_to(source_column: "Data", type: "jsonb")} }

      it "counts every value as fitting" do
        expect(result.columns["data"].type_compatibility).to eq(fits: 2, total: 2)
      end

      it "lists no value as not fitting" do
        expect(result.columns["data"].distinct_values[:incompatible].values).to be_empty
      end
    end

    context "with one column for each family of target types" do
      let(:csv) do
        <<~CSV
          Id,Price,Active,Joined,Ref
          1,9.99,yes,2026-10-10,123e4567-e89b-12d3-a456-426614174000
          2,10,no,03/04/2025,123e4567-e89b-12d3-a456-426614174001
          x3,abc,1,25/12/2025,not-a-uuid
        CSV
      end
      let(:mapped_columns) do
        {
          "id" => maps_to(source_column: "Id", type: "integer"),
          "price" => maps_to(source_column: "Price", type: "decimal"),
          "active" => maps_to(source_column: "Active", type: "boolean"),
          "joined" => maps_to(source_column: "Joined", type: "date"),
          "ref" => maps_to(source_column: "Ref", type: "uuid")
        }
      end

      it "counts 2 of 3 integer values as fitting" do
        expect(result.columns["id"].type_compatibility).to eq(fits: 2, total: 3)
      end

      it "counts 2 of 3 decimal values as fitting" do
        expect(result.columns["price"].type_compatibility).to eq(fits: 2, total: 3)
      end

      it "counts 3 of 3 boolean values as fitting" do
        expect(result.columns["active"].type_compatibility).to eq(fits: 3, total: 3)
      end

      it "counts 1 of 3 date values as fitting" do
        expect(result.columns["joined"].type_compatibility).to eq(fits: 1, total: 3)
      end

      it "counts 2 of 3 uuid values as fitting" do
        expect(result.columns["ref"].type_compatibility).to eq(fits: 2, total: 3)
      end

      it "lists the values that do not fit, so a value mapping can be written for them" do
        expect(result.columns["joined"].distinct_values[:incompatible].values)
          .to eq([{value: "03/04/2025", count: 1}, {value: "25/12/2025", count: 1}])
      end
    end

    context "when the file has a header and no data rows" do
      let(:csv) { "A,B\n" }
      let(:mapped_columns) { {"b" => maps_to(source_column: "B", type: "integer"), "a" => maps_to(source_column: "A", type: "string")} }

      it "counts no rows" do
        expect(result.row_count).to eq(0)
      end

      it "lists the mapped columns with the positions of their source columns" do
        expect(result.columns.transform_values(&:position)).to eq("a" => 1, "b" => 2)
      end

      it "shows every mapped column with zero counts" do
        expect(result.columns["b"]).to have_attributes(
          empty: 0,
          type_compatibility: {fits: 0, total: 0}
        )
      end

      it "lists no values" do
        expect(result.columns["b"].distinct_values.values).to all(have_attributes(value_counts: {}))
      end
    end

    context "when every row of the file is empty" do
      let(:csv) { "A,B\n,\n  ,  \n\n" }
      let(:mapped_columns) { {"a" => maps_to(source_column: "A", type: "string")} }

      it "counts no rows and shows zero counts" do
        expect(result.row_count).to eq(0)
        expect(result.columns["a"].empty).to eq(0)
      end
    end

    context "when a row in the middle of the file is empty" do
      let(:csv) { "A,B\n1,2\n,\n3,4\n" }
      let(:mapped_columns) { {"a" => maps_to(source_column: "A", type: "integer")} }

      it "does not count the empty row" do
        expect(result.row_count).to eq(2)
      end
    end

    context "when a row has more cells than the header" do
      let(:csv) { "A,B,C\n1,2,3,4\n5,6,7\n" }
      let(:mapped_columns) { {"a" => maps_to(source_column: "A", type: "integer"), "c" => maps_to(source_column: "C", type: "integer")} }

      it "stops with source_row_too_long, with the line of the row" do
        expect { result }.to raise_error(Pipeforge::Source::MalformedSourceError) do |error|
          expect(error.errors.map { |entry| entry.slice(:code, :line) }).to eq([{code: :source_row_too_long, line: 2}])
        end
      end
    end

    context "when the header has a blank cell" do
      let(:csv) { "A,,C\n1,2,3\n" }
      let(:mapped_columns) { {"a" => maps_to(source_column: "A", type: "integer")} }

      it "stops with source_header_blank, even though the blank cell is not mapped" do
        expect { result }.to raise_error(Pipeforge::Source::InvalidHeaderError) do |error|
          expect(error.errors.map { |entry| entry.slice(:code, :position) }).to eq([{code: :source_header_blank, position: 2}])
        end
      end
    end

    context "when a name appears twice in the header" do
      let(:csv) { "A,A\n1,2\n" }
      let(:mapped_columns) { {"a" => maps_to(source_column: "A", type: "integer")} }

      it "stops with source_header_duplicated" do
        expect { result }.to raise_error(Pipeforge::Source::InvalidHeaderError) do |error|
          expect(error.codes).to eq([:source_header_duplicated])
        end
      end
    end

    context "when the file is empty" do
      let(:csv) { "" }
      let(:mapped_columns) { {"a" => maps_to(source_column: "A", type: "integer")} }

      it "stops with source_empty" do
        expect { result }.to raise_error(Pipeforge::Source::EmptySourceError) do |error|
          expect(error.codes).to eq([:source_empty])
        end
      end
    end

    context "when a row cannot be parsed" do
      # The quote opened on line 3 is never closed, so it swallows lines 4 to 6.
      let(:csv) { "Name,Note\nAlice,30\nBob,\"two lines\nof text\nCara,25\nDan,40\n" }
      let(:mapped_columns) { {"name" => maps_to(source_column: "Name", type: "string")} }

      it "stops with our own error, naming the line where the row starts" do
        expect { result }.to raise_error(Pipeforge::Source::MalformedSourceError, /malformed CSV at line 3: .*quote/i) do |error|
          expect(error.line).to eq(3)
        end
      end
    end

    context "with padded values and headers" do
      let(:csv) { " Id , Name \n 42 ,Alice\n\t7\t,  \n" }
      let(:mapped_columns) { {"id" => maps_to(source_column: "Id", type: "integer"), "name" => maps_to(source_column: "Name", type: "string")} }

      it "trims the headers, so the mapping uses the trimmed names" do
        expect(result.columns.keys).to eq(%w[id name])
      end

      it "checks the type on the trimmed value" do
        expect(result.columns["id"].type_compatibility).to eq(fits: 2, total: 2)
      end

      it "counts a value of only whitespace as empty" do
        expect(result.columns["name"].empty).to eq(1)
      end
    end

    context "when a row has fewer fields than the header" do
      let(:csv) { "A,B,C\n1,2\n3,4,5\n" }
      let(:mapped_columns) { {"c" => maps_to(source_column: "C", type: "integer")} }

      it "counts the missing value as empty" do
        expect(result.columns["c"]).to have_attributes(empty: 1, type_compatibility: {fits: 1, total: 1})
      end
    end

    context "with quoted values" do
      let(:csv) { "A,B\n\"x, y\",\"say \"\"hi\"\"\"\n" }
      let(:mapped_columns) { {"a" => maps_to(source_column: "A", type: "string"), "b" => maps_to(source_column: "B", type: "string")} }

      it "keeps a comma inside quotes as part of the value" do
        expect(result.columns["a"].distinct_values[:compatible].values).to eq([{value: "x, y", count: 1}])
      end

      it "reads a doubled quote as one quote" do
        expect(result.columns["b"].distinct_values[:compatible].values).to eq([{value: "say \"hi\"", count: 1}])
      end
    end

    context "with values that differ only in case" do
      let(:csv) { "S\nActive\nactive\nACTIVE\n" }
      let(:mapped_columns) { {"s" => maps_to(source_column: "S", type: "string")} }

      it "keeps them as different values" do
        expect(result.columns["s"].distinct_values[:compatible].values.map { |listed| listed[:value] })
          .to eq(%w[Active active ACTIVE])
      end
    end

    context "with text that is not ASCII" do
      let(:csv) { "S\nÉcole\n日本語日本語\n" }
      let(:mapped_columns) { {"s" => maps_to(source_column: "S", type: "string", max_length: 5)} }

      it "measures the length in characters, not bytes" do
        expect(result.columns["s"].type_compatibility).to eq(fits: 1, total: 2)
      end
    end

    context "when the source is a file" do
      let(:file) { File.open(csv_file(csv)) }
      let(:source_reader) { Pipeforge::Source::CsvReader.new(source_io: Pipeforge::Source::ReusableIO.new(io: file)) }

      it "names the source by its file path" do
        expect(result.source_identifier).to eq(file.path)
      end
    end

    context "with a different chunk size" do
      let(:default_result) { result_with({}) }

      shared_examples "the same result as the default chunk size" do
        it "gives the same result as the default chunk size" do
          expect(result.to_h).to eq(default_result.to_h)
        end
      end

      context "of 1 row" do
        let(:settings) { {execution: {batch_size: 1}} }

        include_examples "the same result as the default chunk size"
      end

      context "of 2 rows" do
        let(:settings) { {execution: {batch_size: 2}} }

        include_examples "the same result as the default chunk size"
      end

      context "of 3 rows" do
        let(:settings) { {execution: {batch_size: 3}} }

        include_examples "the same result as the default chunk size"
      end

      context "of 100 rows, more than the file has" do
        let(:settings) { {execution: {batch_size: 100}} }

        include_examples "the same result as the default chunk size"
      end

      context "of 1 row, with several rows in the file" do
        let(:settings) { {execution: {batch_size: 1}} }

        it "builds one type checker for each mapped column, however many chunks are read" do
          allow(Pipeforge::ValueAnalyzer::TypeChecker).to receive(:new).and_call_original

          result

          expect(Pipeforge::ValueAnalyzer::TypeChecker).to have_received(:new).exactly(mapped_columns.size).times
        end
      end
    end

    context "with a cap on the distinct values" do
      # Status: Active x4 (one written " Active "), INACTIVE x2, A x1. Code: seven different values.
      let(:csv) do
        <<~CSV
          Status,Code
          Active,a1
          INACTIVE,b2
          Active, c3
          A,d4
          Active,e5
          INACTIVE,f6
           Active ,g7
        CSV
      end
      let(:mapped_columns) { {"status" => maps_to(source_column: "Status", type: "string"), "code" => maps_to(source_column: "Code", type: "string")} }
      let(:cap) { 2 }
      let(:settings) { {source: {distinct_values_cap: cap}} }

      def listed(target_column:, list: :compatible)
        result.columns[target_column].distinct_values[list].values
      end

      it "lists the values that appeared first, up to the cap" do
        expect(listed(target_column: "code")).to eq([{value: "a1", count: 1}, {value: "b2", count: 1}])
      end

      it "keeps the counts of the listed values exact" do
        expect(listed(target_column: "status")).to eq([{value: "Active", count: 4}, {value: "INACTIVE", count: 2}])
      end

      it "still counts every value in the totals" do
        expect(result.columns["code"].type_compatibility).to eq(fits: 7, total: 7)
      end

      context "when the file is read one row at a time" do
        let(:settings) do
          {execution: {batch_size: 1}, source: {distinct_values_cap: cap}}
        end

        it "keeps the counts of the listed values exact" do
          expect(listed(target_column: "status")).to eq([{value: "Active", count: 4}, {value: "INACTIVE", count: 2}])
        end
      end
    end

    context "with a cap smaller than the values of both lists" do
      let(:csv) { "N\n1\n2\n3\nx\ny\nz\n" }
      let(:mapped_columns) { {"n" => maps_to(source_column: "N", type: "integer")} }
      let(:settings) { {source: {distinct_values_cap: 2}} }

      it "caps each list on its own" do
        distinct_values = result.columns["n"].distinct_values

        expect(distinct_values[:compatible].values).to eq([{value: "1", count: 1}, {value: "2", count: 1}])
        expect(distinct_values[:incompatible].values).to eq([{value: "x", count: 1}, {value: "y", count: 1}])
      end

      it "still counts every value in the totals" do
        expect(result.columns["n"].type_compatibility).to eq(fits: 3, total: 6)
      end
    end

    context "with a value mapping on a column" do
      let(:csv) { "Status\nActive\nInactive\nActive\nn/a\nbroken\n" }
      let(:mapped_columns) { {"status" => maps_to(source_column: "Status", type: "integer", value_mapping: value_mapping)} }
      let(:value_mapping) { {"Active" => "1", "Inactive" => "0", "n/a" => nil} }

      it "measures a mapped value as the value it maps to" do
        expect(result.columns["status"].type_compatibility).to eq(fits: 3, total: 4)
      end

      it "lists the values that would be loaded, not the values in the file" do
        expect(result.columns["status"].distinct_values[:compatible].values)
          .to eq([{value: "1", count: 2}, {value: "0", count: 1}])
      end

      context "when two values map to the same value" do
        let(:value_mapping) { {"Active" => "1", "Inactive" => "1"} }

        it "lists them as one value, with their counts added" do
          expect(result.columns["status"].distinct_values[:compatible].values).to eq([{value: "1", count: 3}])
        end
      end

      context "when the mapping has a value that is not in the file" do
        let(:value_mapping) { {"Active" => "1", "Never seen" => "9"} }

        it "ignores it when measuring" do
          expect(result.columns["status"].type_compatibility).to eq(fits: 2, total: 5)
        end

        it "still returns it with the column" do
          expect(result.columns["status"].value_mapping).to include("Never seen" => "9")
        end
      end

      context "when the file has the value with spaces around it" do
        let(:csv) { "Status\n Active \nActive\n" }
        let(:value_mapping) { {"Active" => "1"} }

        it "applies the mapping to the trimmed value" do
          expect(result.columns["status"].distinct_values[:compatible].values).to eq([{value: "1", count: 2}])
        end
      end

      context "when the file has no data rows" do
        let(:csv) { "Status\n" }

        it "returns the value mapping with the zero counts" do
          expect(result.columns["status"]).to have_attributes(
            type_compatibility: {fits: 0, total: 0},
            value_mapping: value_mapping
          )
        end
      end

      it "keeps listing the values that still do not fit" do
        expect(result.columns["status"].distinct_values[:incompatible].values)
          .to eq([{value: "broken", count: 1}])
      end

      it "counts a value that maps to nothing as empty, and leaves it out of both lists" do
        expect(result.columns["status"].empty).to eq(1)
      end

      it "returns the value mapping with the column, so it can be edited and passed in again" do
        expect(result.columns["status"].value_mapping).to eq("Active" => "1", "Inactive" => "0", "n/a" => nil)
      end

      context "when a value maps to a blank" do
        let(:value_mapping) { {"n/a" => "  ", "broken" => ""} }

        it "counts it as empty" do
          expect(result.columns["status"].empty).to eq(2)
        end
      end

      context "when a value maps to something that is not text" do
        let(:value_mapping) { {"Active" => 1} }

        it "measures and lists it as its text" do
          expect(result.columns["status"].distinct_values[:compatible].values).to eq([{value: "1", count: 2}])
        end
      end

      context "when a value maps to a value that does not fit either" do
        let(:value_mapping) { {"Active" => "yes"} }

        it "lists the value it maps to among the values that do not fit" do
          expect(result.columns["status"].distinct_values[:incompatible].values).to include({value: "yes", count: 2})
        end
      end

      context "when another column has no value mapping" do
        let(:csv) { "Status,Age\nActive,30\nx,y\n" }
        let(:mapped_columns) do
          {
            "status" => maps_to(source_column: "Status", type: "integer", value_mapping: {"Active" => "1"}),
            "age" => maps_to(source_column: "Age", type: "integer")
          }
        end

        it "gives that column an empty value mapping" do
          expect(result.columns["age"].value_mapping).to eq({})
        end

        it "measures that column on its raw values" do
          expect(result.columns["age"].type_compatibility).to eq(fits: 1, total: 2)
        end
      end

      context "when the file is read in small chunks" do
        let(:settings) { {execution: {batch_size: 1}} }
        let(:default_result) { result_with({}) }

        it "gives the same result as the default chunk size" do
          expect(result.to_h).to eq(default_result.to_h)
        end
      end
    end

    context "when a value maps to false" do
      let(:csv) { "Flag\nNo\nNo\nYes\n" }
      let(:mapped_columns) { {"flag" => maps_to(source_column: "Flag", type: "boolean", value_mapping: {"No" => false})} }

      it "loads false as a value, not as empty" do
        expect(result.columns["flag"]).to have_attributes(empty: 0, type_compatibility: {fits: 3, total: 3})
      end

      it "lists it as false" do
        expect(result.columns["flag"].distinct_values[:compatible].values)
          .to eq([{value: "false", count: 2}, {value: "Yes", count: 1}])
      end
    end

    context "without a value mapping" do
      it "gives every column an empty value mapping" do
        expect(result.columns.values.map(&:value_mapping)).to all(eq({}))
      end
    end
  end

  describe "source_fingerprint" do
    subject(:result) { described_class.call(source_reader: csv_reader(csv), mapped_columns: mapped_columns) }

    let(:mapped_columns) { {"a" => maps_to(source_column: "A", type: "string")} }

    context "when the setting is off" do
      let(:csv) { "A\n1\n2\n" }

      it "is nil" do
        expect(result.source_fingerprint).to be_nil
      end
    end

    context "when the setting is on" do
      let(:settings) { {source: {fingerprint: true}} }
      let(:csv) { "A\n1\n2\n" }

      it "is the fingerprint of each row as a JSON array of its values, one row per line" do
        expected_fingerprint = Pipeforge::Fingerprint.new
        expected_fingerprint.add(text: "[\"1\"]\n")
        expected_fingerprint.add(text: "[\"2\"]\n")
        expected = expected_fingerprint.value

        expect(result.source_fingerprint).to eq(expected)
      end

      it "is the same however the file is read in chunks" do
        fingerprint_in_one_chunk = result.source_fingerprint
        other = result_with(source: {fingerprint: true}, execution: {batch_size: 1})

        expect(other.source_fingerprint).to eq(fingerprint_in_one_chunk)
      end

      it "changes when a value changes" do
        changed = described_class.call(source_reader: csv_reader("A\n1\n3\n"), mapped_columns: mapped_columns)

        expect(changed.source_fingerprint).not_to eq(result.source_fingerprint)
      end

      context "when a comma inside a value could be mistaken for a separator" do
        let(:mapped_columns) do
          {"a" => maps_to(source_column: "A", type: "string"), "b" => maps_to(source_column: "B", type: "string")}
        end
        let(:csv) { "A,B\n\"a,b\",c\n" }

        it "gives a different fingerprint from the same values split the other way" do
          split_the_other_way = described_class.call(
            source_reader: csv_reader("A,B\na,\"b,c\"\n"), mapped_columns: mapped_columns
          )

          expect(split_the_other_way.source_fingerprint).not_to eq(result.source_fingerprint)
        end
      end
    end
  end

  describe "Result#to_h" do
    subject(:stored) { JSON.parse(JSON.generate(result.to_h)) }

    let(:result) do
      described_class.call(
        source_reader: csv_reader("Age\n30\nx\n\n"),
        mapped_columns: {"age" => maps_to(source_column: "Age", type: "integer")}
      )
    end

    it "survives a round trip through JSON" do
      expect(stored).to eq(
        "source_identifier" => result.source_identifier,
        "row_count" => 2,
        "source_fingerprint" => nil,
        "columns" => {
          "age" => {
            "source_column" => "Age",
            "position" => 1,
            "empty" => 0,
            "type_compatibility" => {"fits" => 1, "total" => 2},
            "distinct_values" => {
              "compatible" => [{"value" => "30", "count" => 1}],
              "incompatible" => [{"value" => "x", "count" => 1}]
            },
            "value_mapping" => {}
          }
        }
      )
    end
  end
end
