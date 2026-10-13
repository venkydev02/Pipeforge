# frozen_string_literal: true

require "json"

RSpec.describe Pipeforge::ValueAnalyzer do
  subject(:analyzer) { described_class.new(config: config) }

  let(:config) { build_configuration }

  # One mapping value: the target column of a source column and the type of that column.
  def maps_to(target_column:, type:, **type_info)
    {target_column: target_column, type: type}.merge(type_info)
  end

  describe "#call" do
    subject(:result) { analyzer.call(path: path, mapped_columns: mapped_columns) }

    let(:path) { csv_file(csv) }
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
        "Full Name" => maps_to(target_column: "name", type: "string"),
        "Age" => maps_to(target_column: "age", type: "integer"),
        "Notes" => maps_to(target_column: "notes", type: "text")
      }
    end

    context "with a typical file" do
      it "names the source file" do
        expect(result.source_identifier).to eq(path)
      end

      it "counts the data rows, not the blank line" do
        expect(result.row_count).to eq(4)
      end

      it "has one summary per mapped column, keyed by source column, in file order" do
        expect(result.columns.keys).to eq(["Full Name", "Age", "Notes"])
      end

      it "gives each summary its target column and its position in the file" do
        expect(result.columns).to include(
          "Full Name" => have_attributes(target_column: "name", position: 1),
          "Age" => have_attributes(target_column: "age", position: 2),
          "Notes" => have_attributes(target_column: "notes", position: 3)
        )
      end

      it "counts empty and whitespace-only cells as empty" do
        expect(result.columns.transform_values(&:empty)).to eq("Full Name" => 1, "Age" => 1, "Notes" => 2)
      end

      it "counts the non-empty values that fit the target type" do
        expect(result.columns["Age"].type_compatibility).to eq(fits: 2, total: 3)
      end

      it "lists the values that fit, with their counts" do
        expect(result.columns["Age"].distinct_values[:compatible].values)
          .to eq([{value: "30", count: 1}, {value: "25", count: 1}])
      end

      it "lists the values that do not fit, with their counts" do
        expect(result.columns["Age"].distinct_values[:incompatible].values).to eq([{value: "x", count: 1}])
      end

      it "leaves empty values out of both lists" do
        notes = result.columns["Notes"].distinct_values

        expect(notes[:compatible].values.map { |listed| listed[:value] }).to eq(["first line\nsecond line", "hi"])
        expect(notes[:incompatible].values).to be_empty
      end
    end

    context "when only some of the columns are mapped" do
      let(:mapped_columns) { {"Age" => maps_to(target_column: "age", type: "integer")} }

      it "measures only the mapped columns" do
        expect(result.columns.keys).to eq(["Age"])
      end

      it "keeps the position the column has in the file" do
        expect(result.columns["Age"].position).to eq(2)
      end
    end

    context "when the mapping lists the columns in another order than the file" do
      let(:mapped_columns) do
        {
          "Notes" => maps_to(target_column: "notes", type: "text"),
          "Age" => maps_to(target_column: "age", type: "integer"),
          "Full Name" => maps_to(target_column: "name", type: "string")
        }
      end

      it "returns the columns in file order" do
        expect(result.columns.keys).to eq(["Full Name", "Age", "Notes"])
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
      let(:mapped_columns) { {"Full Name" => maps_to(target_column: "name", type: "string", max_length: 3)} }

      it "counts the values within the limit as fitting" do
        expect(result.columns["Full Name"].type_compatibility).to eq(fits: 1, total: 3)
      end

      it "lists the values over the limit as not fitting" do
        expect(result.columns["Full Name"].distinct_values[:incompatible].values)
          .to eq([{value: "Alice", count: 1}, {value: "Cara", count: 1}])
      end
    end

    context "when the target type has no fit rule yet" do
      let(:csv) { "Data\n{\"a\": 1}\nnot json\n" }
      let(:mapped_columns) { {"Data" => maps_to(target_column: "data", type: "jsonb")} }

      it "counts every value as fitting" do
        expect(result.columns["Data"].type_compatibility).to eq(fits: 2, total: 2)
      end

      it "lists no value as not fitting" do
        expect(result.columns["Data"].distinct_values[:incompatible].values).to be_empty
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
          "Id" => maps_to(target_column: "id", type: "integer"),
          "Price" => maps_to(target_column: "price", type: "decimal"),
          "Active" => maps_to(target_column: "active", type: "boolean"),
          "Joined" => maps_to(target_column: "joined", type: "date"),
          "Ref" => maps_to(target_column: "ref", type: "uuid")
        }
      end

      it "counts 2 of 3 integer values as fitting" do
        expect(result.columns["Id"].type_compatibility).to eq(fits: 2, total: 3)
      end

      it "counts 2 of 3 decimal values as fitting" do
        expect(result.columns["Price"].type_compatibility).to eq(fits: 2, total: 3)
      end

      it "counts 3 of 3 boolean values as fitting" do
        expect(result.columns["Active"].type_compatibility).to eq(fits: 3, total: 3)
      end

      it "counts 1 of 3 date values as fitting" do
        expect(result.columns["Joined"].type_compatibility).to eq(fits: 1, total: 3)
      end

      it "counts 2 of 3 uuid values as fitting" do
        expect(result.columns["Ref"].type_compatibility).to eq(fits: 2, total: 3)
      end

      it "lists the values that do not fit, so a value mapping can be written for them" do
        expect(result.columns["Joined"].distinct_values[:incompatible].values)
          .to eq([{value: "03/04/2025", count: 1}, {value: "25/12/2025", count: 1}])
      end
    end

    context "when the file has a header and no data rows" do
      let(:csv) { "A,B\n" }
      let(:mapped_columns) { {"B" => maps_to(target_column: "b", type: "integer"), "A" => maps_to(target_column: "a", type: "string")} }

      it "counts no rows" do
        expect(result.row_count).to eq(0)
      end

      it "lists the mapped columns in file order, with their positions" do
        expect(result.columns.transform_values(&:position)).to eq("A" => 1, "B" => 2)
      end

      it "shows every mapped column with zero counts" do
        expect(result.columns["B"]).to have_attributes(
          empty: 0,
          type_compatibility: {fits: 0, total: 0}
        )
      end

      it "lists no values" do
        expect(result.columns["B"].distinct_values.values).to all(have_attributes(value_counts: {}))
      end
    end

    context "when every row of the file is empty" do
      let(:csv) { "A,B\n,\n  ,  \n\n" }
      let(:mapped_columns) { {"A" => maps_to(target_column: "a", type: "string")} }

      it "counts no rows and shows zero counts" do
        expect(result.row_count).to eq(0)
        expect(result.columns["A"].empty).to eq(0)
      end
    end

    context "when a row in the middle of the file is empty" do
      let(:csv) { "A,B\n1,2\n,\n3,4\n" }
      let(:mapped_columns) { {"A" => maps_to(target_column: "a", type: "integer")} }

      it "does not count the empty row" do
        expect(result.row_count).to eq(2)
      end
    end

    context "when the header has a blank cell and a row has extra cells" do
      let(:csv) { "A,,C\n1,2,3,4\n5,6,7\n" }
      let(:mapped_columns) { {"A" => maps_to(target_column: "a", type: "integer"), "C" => maps_to(target_column: "c", type: "integer")} }

      it "does not stop for columns that are not mapped" do
        expect { result }.not_to raise_error
      end

      it "keeps the position of a column that follows the blank header cell" do
        expect(result.columns["C"].position).to eq(3)
      end
    end

    context "when a mapped column is not in the header" do
      let(:csv) { "A,B\n1,2\n" }
      let(:mapped_columns) do
        {"A" => maps_to(target_column: "a", type: "string"), "Nope" => maps_to(target_column: "nope", type: "string"), "Gone" => maps_to(target_column: "gone", type: "string")}
      end

      it "raises, naming every missing column" do
        expect { result }.to raise_error(
          Pipeforge::Source::MissingColumnError, "mapped source columns not found in the file: Nope, Gone"
        )
      end

      it "has an entry with the code mapped_column_not_in_file for each missing column" do
        expect { result }.to raise_error(Pipeforge::Source::MissingColumnError) do |error|
          expect(error.errors.map { |entry| entry.slice(:code, :source_column) }).to eq(
            [
              {code: :mapped_column_not_in_file, source_column: "Nope"},
              {code: :mapped_column_not_in_file, source_column: "Gone"}
            ]
          )
        end
      end

      context "and the file has no data rows" do
        let(:csv) { "A,B\n" }

        it "raises as well" do
          expect { result }.to raise_error(Pipeforge::Source::MissingColumnError, /Nope, Gone/)
        end
      end
    end

    context "when a mapping value is incomplete" do
      let(:csv) { "A,B\n1,2\n" }

      context "without a target column" do
        let(:mapped_columns) { {"A" => {type: "string"}} }

        it "raises IncompleteColumnsError, naming the source column" do
          expect { result }.to raise_error(
            Pipeforge::IncompleteColumnsError, "mapped columns are incomplete: A has no target_column"
          )
        end

        it "gives the code column_missing_target_column, with the column" do
          expect { result }.to raise_error(Pipeforge::IncompleteColumnsError) do |error|
            expect(error.errors).to eq(
              [{code: :column_missing_target_column, message: "A has no target_column", source_column: "A"}]
            )
          end
        end
      end

      context "without a type" do
        let(:mapped_columns) { {"A" => {target_column: "a"}} }

        it "raises IncompleteColumnsError, naming the source column" do
          expect { result }.to raise_error(Pipeforge::IncompleteColumnsError, "mapped columns are incomplete: A has no type")
        end

        it "gives the code column_missing_type, with the column" do
          expect { result }.to raise_error(Pipeforge::IncompleteColumnsError) do |error|
            expect(error.errors.map { |entry| entry.slice(:code, :source_column) }).to eq(
              [{code: :column_missing_type, source_column: "A"}]
            )
          end
        end
      end

      context "in several columns" do
        let(:mapped_columns) do
          {"A" => {type: "string"}, "B" => {}, "C" => {target_column: "c", type: "string"}}
        end

        it "lists every error in one error" do
          expect { result }.to raise_error(
            Pipeforge::IncompleteColumnsError,
            "mapped columns are incomplete: A has no target_column, B has no target_column, B has no type"
          )
        end

        it "has an entry for each missing piece, in order" do
          expect { result }.to raise_error(Pipeforge::IncompleteColumnsError) do |error|
            expect(error.errors.map { |entry| entry.slice(:code, :source_column) }).to eq(
              [
                {code: :column_missing_target_column, source_column: "A"},
                {code: :column_missing_target_column, source_column: "B"},
                {code: :column_missing_type, source_column: "B"}
              ]
            )
          end
        end
      end

      context "together with a column that is not in the file" do
        let(:mapped_columns) { {"A" => {type: "string"}, "Gone" => {target_column: "g", type: "string"}} }

        it "reports the incomplete column first, before the file is read" do
          expect { result }.to raise_error(Pipeforge::IncompleteColumnsError, /A has no target_column/)
        end
      end
    end

    context "when a row cannot be parsed" do
      # The quote opened on line 3 is never closed, so it swallows lines 4 to 6.
      let(:csv) { "Name,Note\nAlice,30\nBob,\"two lines\nof text\nCara,25\nDan,40\n" }
      let(:mapped_columns) { {"Name" => maps_to(target_column: "name", type: "string")} }

      it "stops with our own error, naming the line where the row starts" do
        expect { result }.to raise_error(Pipeforge::Source::MalformedSourceError, /malformed CSV at line 3: .*quote/i) do |error|
          expect(error.line).to eq(3)
        end
      end
    end

    context "with padded values and headers" do
      let(:csv) { " Id , Name \n 42 ,Alice\n\t7\t,  \n" }
      let(:mapped_columns) { {"Id" => maps_to(target_column: "id", type: "integer"), "Name" => maps_to(target_column: "name", type: "string")} }

      it "trims the headers, so the mapping uses the trimmed names" do
        expect(result.columns.keys).to eq(%w[Id Name])
      end

      it "checks the type on the trimmed value" do
        expect(result.columns["Id"].type_compatibility).to eq(fits: 2, total: 2)
      end

      it "counts a value of only whitespace as empty" do
        expect(result.columns["Name"].empty).to eq(1)
      end
    end

    context "when a row has fewer fields than the header" do
      let(:csv) { "A,B,C\n1,2\n3,4,5\n" }
      let(:mapped_columns) { {"C" => maps_to(target_column: "c", type: "integer")} }

      it "counts the missing value as empty" do
        expect(result.columns["C"]).to have_attributes(empty: 1, type_compatibility: {fits: 1, total: 1})
      end
    end

    context "with quoted values" do
      let(:csv) { "A,B\n\"x, y\",\"say \"\"hi\"\"\"\n" }
      let(:mapped_columns) { {"A" => maps_to(target_column: "a", type: "string"), "B" => maps_to(target_column: "b", type: "string")} }

      it "keeps a comma inside quotes as part of the value" do
        expect(result.columns["A"].distinct_values[:compatible].values).to eq([{value: "x, y", count: 1}])
      end

      it "reads a doubled quote as one quote" do
        expect(result.columns["B"].distinct_values[:compatible].values).to eq([{value: "say \"hi\"", count: 1}])
      end
    end

    context "with values that differ only in case" do
      let(:csv) { "S\nActive\nactive\nACTIVE\n" }
      let(:mapped_columns) { {"S" => maps_to(target_column: "s", type: "string")} }

      it "keeps them as different values" do
        expect(result.columns["S"].distinct_values[:compatible].values.map { |listed| listed[:value] })
          .to eq(%w[Active active ACTIVE])
      end
    end

    context "with text that is not ASCII" do
      let(:csv) { "S\nÉcole\n日本語日本語\n" }
      let(:mapped_columns) { {"S" => maps_to(target_column: "s", type: "string", max_length: 5)} }

      it "measures the length in characters, not bytes" do
        expect(result.columns["S"].type_compatibility).to eq(fits: 1, total: 2)
      end
    end

    context "when the path is a Pathname" do
      let(:path) { Pathname.new(csv_file(csv)) }

      it "names the source as a String" do
        expect(result.source_identifier).to eq(path.to_s)
      end
    end

    context "with a different chunk size" do
      let(:default_result) do
        described_class.new(config: build_configuration).call(path: path, mapped_columns: mapped_columns)
      end

      shared_examples "the same result as the default chunk size" do
        it "gives the same result as the default chunk size" do
          expect(result.to_h).to eq(default_result.to_h)
        end
      end

      context "of 1 row" do
        let(:config) { build_configuration(execution: {batch_size: 1}) }

        include_examples "the same result as the default chunk size"
      end

      context "of 2 rows" do
        let(:config) { build_configuration(execution: {batch_size: 2}) }

        include_examples "the same result as the default chunk size"
      end

      context "of 3 rows" do
        let(:config) { build_configuration(execution: {batch_size: 3}) }

        include_examples "the same result as the default chunk size"
      end

      context "of 100 rows, more than the file has" do
        let(:config) { build_configuration(execution: {batch_size: 100}) }

        include_examples "the same result as the default chunk size"
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
      let(:mapped_columns) { {"Status" => maps_to(target_column: "status", type: "string"), "Code" => maps_to(target_column: "code", type: "string")} }
      let(:cap) { 2 }
      let(:config) { build_configuration(source: {distinct_values_cap: cap}) }

      def listed(source_column:, list: :compatible)
        result.columns[source_column].distinct_values[list].values
      end

      it "lists the values that appeared first, up to the cap" do
        expect(listed(source_column: "Code")).to eq([{value: "a1", count: 1}, {value: "b2", count: 1}])
      end

      it "keeps the counts of the listed values exact" do
        expect(listed(source_column: "Status")).to eq([{value: "Active", count: 4}, {value: "INACTIVE", count: 2}])
      end

      it "still counts every value in the totals" do
        expect(result.columns["Code"].type_compatibility).to eq(fits: 7, total: 7)
      end

      context "when the file is read one row at a time" do
        let(:config) do
          build_configuration(execution: {batch_size: 1}, source: {distinct_values_cap: cap})
        end

        it "keeps the counts of the listed values exact" do
          expect(listed(source_column: "Status")).to eq([{value: "Active", count: 4}, {value: "INACTIVE", count: 2}])
        end
      end
    end

    context "with a cap smaller than the values of both lists" do
      let(:csv) { "N\n1\n2\n3\nx\ny\nz\n" }
      let(:mapped_columns) { {"N" => maps_to(target_column: "n", type: "integer")} }
      let(:config) { build_configuration(source: {distinct_values_cap: 2}) }

      it "caps each list on its own" do
        distinct_values = result.columns["N"].distinct_values

        expect(distinct_values[:compatible].values).to eq([{value: "1", count: 1}, {value: "2", count: 1}])
        expect(distinct_values[:incompatible].values).to eq([{value: "x", count: 1}, {value: "y", count: 1}])
      end

      it "still counts every value in the totals" do
        expect(result.columns["N"].type_compatibility).to eq(fits: 3, total: 6)
      end
    end

    context "with a value mapping on a column" do
      let(:csv) { "Status\nActive\nInactive\nActive\nn/a\nbroken\n" }
      let(:mapped_columns) { {"Status" => maps_to(target_column: "status", type: "integer", value_mapping: value_mapping)} }
      let(:value_mapping) { {"Active" => "1", "Inactive" => "0", "n/a" => nil} }

      it "measures a mapped value as the value it maps to" do
        expect(result.columns["Status"].type_compatibility).to eq(fits: 3, total: 4)
      end

      it "lists the values that would be loaded, not the values in the file" do
        expect(result.columns["Status"].distinct_values[:compatible].values)
          .to eq([{value: "1", count: 2}, {value: "0", count: 1}])
      end

      context "when two values map to the same value" do
        let(:value_mapping) { {"Active" => "1", "Inactive" => "1"} }

        it "lists them as one value, with their counts added" do
          expect(result.columns["Status"].distinct_values[:compatible].values).to eq([{value: "1", count: 3}])
        end
      end

      context "when the mapping has a value that is not in the file" do
        let(:value_mapping) { {"Active" => "1", "Never seen" => "9"} }

        it "ignores it when measuring" do
          expect(result.columns["Status"].type_compatibility).to eq(fits: 2, total: 5)
        end

        it "still returns it with the column" do
          expect(result.columns["Status"].value_mapping).to include("Never seen" => "9")
        end
      end

      context "when the file has the value with spaces around it" do
        let(:csv) { "Status\n Active \nActive\n" }
        let(:value_mapping) { {"Active" => "1"} }

        it "applies the mapping to the trimmed value" do
          expect(result.columns["Status"].distinct_values[:compatible].values).to eq([{value: "1", count: 2}])
        end
      end

      context "when the file has no data rows" do
        let(:csv) { "Status\n" }

        it "returns the value mapping with the zero counts" do
          expect(result.columns["Status"]).to have_attributes(
            type_compatibility: {fits: 0, total: 0},
            value_mapping: value_mapping
          )
        end
      end

      it "keeps listing the values that still do not fit" do
        expect(result.columns["Status"].distinct_values[:incompatible].values)
          .to eq([{value: "broken", count: 1}])
      end

      it "counts a value that maps to nothing as empty, and leaves it out of both lists" do
        expect(result.columns["Status"].empty).to eq(1)
      end

      it "returns the value mapping with the column, so it can be edited and passed in again" do
        expect(result.columns["Status"].value_mapping).to eq("Active" => "1", "Inactive" => "0", "n/a" => nil)
      end

      context "when a value maps to a blank" do
        let(:value_mapping) { {"n/a" => "  ", "broken" => ""} }

        it "counts it as empty" do
          expect(result.columns["Status"].empty).to eq(2)
        end
      end

      context "when a value maps to something that is not text" do
        let(:value_mapping) { {"Active" => 1} }

        it "measures and lists it as its text" do
          expect(result.columns["Status"].distinct_values[:compatible].values).to eq([{value: "1", count: 2}])
        end
      end

      context "when a value maps to a value that does not fit either" do
        let(:value_mapping) { {"Active" => "yes"} }

        it "lists the value it maps to among the values that do not fit" do
          expect(result.columns["Status"].distinct_values[:incompatible].values).to include({value: "yes", count: 2})
        end
      end

      context "when another column has no value mapping" do
        let(:csv) { "Status,Age\nActive,30\nx,y\n" }
        let(:mapped_columns) do
          {
            "Status" => maps_to(target_column: "status", type: "integer", value_mapping: {"Active" => "1"}),
            "Age" => maps_to(target_column: "age", type: "integer")
          }
        end

        it "gives that column an empty value mapping" do
          expect(result.columns["Age"].value_mapping).to eq({})
        end

        it "measures that column on its raw values" do
          expect(result.columns["Age"].type_compatibility).to eq(fits: 1, total: 2)
        end
      end

      context "when the file is read in small chunks" do
        let(:config) { build_configuration(execution: {batch_size: 1}) }
        let(:default_result) do
          described_class.new(config: build_configuration).call(path: path, mapped_columns: mapped_columns)
        end

        it "gives the same result as the default chunk size" do
          expect(result.to_h).to eq(default_result.to_h)
        end
      end
    end

    context "when a value maps to false" do
      let(:csv) { "Flag\nNo\nNo\nYes\n" }
      let(:mapped_columns) { {"Flag" => maps_to(target_column: "flag", type: "boolean", value_mapping: {"No" => false})} }

      it "loads false as a value, not as empty" do
        expect(result.columns["Flag"]).to have_attributes(empty: 0, type_compatibility: {fits: 3, total: 3})
      end

      it "lists it as false" do
        expect(result.columns["Flag"].distinct_values[:compatible].values)
          .to eq([{value: "false", count: 2}, {value: "Yes", count: 1}])
      end
    end

    context "without a value mapping" do
      it "gives every column an empty value mapping" do
        expect(result.columns.values.map(&:value_mapping)).to all(eq({}))
      end
    end
  end

  describe "Result#to_h" do
    subject(:stored) { JSON.parse(JSON.generate(result.to_h)) }

    let(:result) do
      analyzer.call(
        path: csv_file("Age\n30\nx\n\n"),
        mapped_columns: {"Age" => maps_to(target_column: "age", type: "integer")}
      )
    end

    it "survives a round trip through JSON" do
      expect(stored).to eq(
        "source_identifier" => result.source_identifier,
        "row_count" => 2,
        "columns" => {
          "Age" => {
            "target_column" => "age",
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
