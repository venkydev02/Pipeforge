# frozen_string_literal: true

require "json"

RSpec.describe Pipeforge::ValueAnalyzer do
  subject(:analyzer) { described_class.new(config: config) }

  let(:config) { build_configuration }

  # One mapping value: the target column of a source column and the type of that column.
  def maps_to(target_column, type, **type_info)
    {target_column: target_column, type: type}.merge(type_info)
  end

  describe "#call" do
    subject(:result) { analyzer.call(path: path, column_mapping: column_mapping) }

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
    let(:column_mapping) do
      {
        "Full Name" => maps_to("name", "string"),
        "Age" => maps_to("age", "integer"),
        "Notes" => maps_to("notes", "text")
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
      let(:column_mapping) { {"Age" => maps_to("age", "integer")} }

      it "measures only the mapped columns" do
        expect(result.columns.keys).to eq(["Age"])
      end

      it "keeps the position the column has in the file" do
        expect(result.columns["Age"].position).to eq(2)
      end
    end

    context "when the mapping lists the columns in another order than the file" do
      let(:column_mapping) do
        {
          "Notes" => maps_to("notes", "text"),
          "Age" => maps_to("age", "integer"),
          "Full Name" => maps_to("name", "string")
        }
      end

      it "returns the columns in file order" do
        expect(result.columns.keys).to eq(["Full Name", "Age", "Notes"])
      end
    end

    context "when the mapping is empty" do
      let(:column_mapping) { {} }

      it "measures no column" do
        expect(result.columns).to be_empty
      end

      it "still counts the rows" do
        expect(result.row_count).to eq(4)
      end
    end

    context "when the target type limits the length of the text" do
      let(:column_mapping) { {"Full Name" => maps_to("name", "string", max_length: 3)} }

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
      let(:column_mapping) { {"Data" => maps_to("data", "jsonb")} }

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
      let(:column_mapping) do
        {
          "Id" => maps_to("id", "integer"),
          "Price" => maps_to("price", "decimal"),
          "Active" => maps_to("active", "boolean"),
          "Joined" => maps_to("joined", "date"),
          "Ref" => maps_to("ref", "uuid")
        }
      end

      {"Id" => [2, 3], "Price" => [2, 3], "Active" => [3, 3], "Joined" => [1, 3], "Ref" => [2, 3]}.each do |source_column, (fits, total)|
        it "counts #{fits} of #{total} #{source_column} values as fitting" do
          expect(result.columns[source_column].type_compatibility).to eq(fits: fits, total: total)
        end
      end

      it "lists the values that do not fit, so a value mapping can be written for them" do
        expect(result.columns["Joined"].distinct_values[:incompatible].values)
          .to eq([{value: "03/04/2025", count: 1}, {value: "25/12/2025", count: 1}])
      end
    end

    context "when the file has a header and no data rows" do
      let(:csv) { "A,B\n" }
      let(:column_mapping) { {"B" => maps_to("b", "integer"), "A" => maps_to("a", "string")} }

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
      let(:column_mapping) { {"A" => maps_to("a", "string")} }

      it "counts no rows and shows zero counts" do
        expect(result.row_count).to eq(0)
        expect(result.columns["A"].empty).to eq(0)
      end
    end

    context "when a row in the middle of the file is empty" do
      let(:csv) { "A,B\n1,2\n,\n3,4\n" }
      let(:column_mapping) { {"A" => maps_to("a", "integer")} }

      it "does not count the empty row" do
        expect(result.row_count).to eq(2)
      end
    end

    context "when the header has a blank cell and a row has extra cells" do
      let(:csv) { "A,,C\n1,2,3,4\n5,6,7\n" }
      let(:column_mapping) { {"A" => maps_to("a", "integer"), "C" => maps_to("c", "integer")} }

      it "does not stop for columns that are not mapped" do
        expect { result }.not_to raise_error
      end

      it "keeps the position of a column that follows the blank header cell" do
        expect(result.columns["C"].position).to eq(3)
      end
    end

    context "when a mapped column is not in the header" do
      let(:csv) { "A,B\n1,2\n" }
      let(:column_mapping) do
        {"A" => maps_to("a", "string"), "Nope" => maps_to("nope", "string"), "Gone" => maps_to("gone", "string")}
      end

      it "raises, naming every missing column" do
        expect { result }.to raise_error(
          Pipeforge::Source::MissingColumnError, "mapped source columns not found in the file: Nope, Gone"
        )
      end

      context "and the file has no data rows" do
        let(:csv) { "A,B\n" }

        it "raises as well" do
          expect { result }.to raise_error(Pipeforge::Source::MissingColumnError, /Nope, Gone/)
        end
      end
    end

    context "when a mapping value is incomplete" do
      let(:csv) { "A\n1\n" }

      context "without a target column" do
        let(:column_mapping) { {"A" => {type: "string"}} }

        it "raises KeyError, naming the source column" do
          expect { result }.to raise_error(KeyError, /source column A has no target_column/)
        end
      end

      context "without a type" do
        let(:column_mapping) { {"A" => {target_column: "a"}} }

        it "raises KeyError" do
          expect { result }.to raise_error(KeyError)
        end
      end
    end

    context "when a row cannot be parsed" do
      # The quote opened on line 3 is never closed, so it swallows lines 4 to 6.
      let(:csv) { "Name,Note\nAlice,30\nBob,\"two lines\nof text\nCara,25\nDan,40\n" }
      let(:column_mapping) { {"Name" => maps_to("name", "string")} }

      it "stops with our own error, naming the line where the row starts" do
        expect { result }.to raise_error(Pipeforge::Source::MalformedSourceError, /malformed CSV at line 3: .*quote/i) do |error|
          expect(error.line).to eq(3)
        end
      end
    end

    context "with padded values and headers" do
      let(:csv) { " Id , Name \n 42 ,Alice\n\t7\t,  \n" }
      let(:column_mapping) { {"Id" => maps_to("id", "integer"), "Name" => maps_to("name", "string")} }

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
      let(:column_mapping) { {"C" => maps_to("c", "integer")} }

      it "counts the missing value as empty" do
        expect(result.columns["C"]).to have_attributes(empty: 1, type_compatibility: {fits: 1, total: 1})
      end
    end

    context "with quoted values" do
      let(:csv) { "A,B\n\"x, y\",\"say \"\"hi\"\"\"\n" }
      let(:column_mapping) { {"A" => maps_to("a", "string"), "B" => maps_to("b", "string")} }

      it "keeps a comma inside quotes as part of the value" do
        expect(result.columns["A"].distinct_values[:compatible].values).to eq([{value: "x, y", count: 1}])
      end

      it "reads a doubled quote as one quote" do
        expect(result.columns["B"].distinct_values[:compatible].values).to eq([{value: "say \"hi\"", count: 1}])
      end
    end

    context "with values that differ only in case" do
      let(:csv) { "S\nActive\nactive\nACTIVE\n" }
      let(:column_mapping) { {"S" => maps_to("s", "string")} }

      it "keeps them as different values" do
        expect(result.columns["S"].distinct_values[:compatible].values.map { |listed| listed[:value] })
          .to eq(%w[Active active ACTIVE])
      end
    end

    context "with text that is not ASCII" do
      let(:csv) { "S\nÉcole\n日本語日本語\n" }
      let(:column_mapping) { {"S" => maps_to("s", "string", max_length: 5)} }

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
        described_class.new(config: build_configuration).call(path: path, column_mapping: column_mapping)
      end

      [1, 2, 3, 100].each do |batch_size|
        context "of #{batch_size} rows" do
          let(:config) { build_configuration(execution: {batch_size: batch_size}) }

          it "gives the same result as the default chunk size" do
            expect(result.to_h).to eq(default_result.to_h)
          end
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
      let(:column_mapping) { {"Status" => maps_to("status", "string"), "Code" => maps_to("code", "string")} }
      let(:cap) { 2 }
      let(:config) { build_configuration(source: {distinct_values_cap: cap}) }

      def listed(source_column, list = :compatible)
        result.columns[source_column].distinct_values[list].values
      end

      it "lists the values that appeared first, up to the cap" do
        expect(listed("Code")).to eq([{value: "a1", count: 1}, {value: "b2", count: 1}])
      end

      it "keeps the counts of the listed values exact" do
        expect(listed("Status")).to eq([{value: "Active", count: 4}, {value: "INACTIVE", count: 2}])
      end

      it "still counts every value in the totals" do
        expect(result.columns["Code"].type_compatibility).to eq(fits: 7, total: 7)
      end

      context "when the file is read one row at a time" do
        let(:config) do
          build_configuration(execution: {batch_size: 1}, source: {distinct_values_cap: cap})
        end

        it "keeps the counts of the listed values exact" do
          expect(listed("Status")).to eq([{value: "Active", count: 4}, {value: "INACTIVE", count: 2}])
        end
      end
    end

    context "with a cap smaller than the values of both lists" do
      let(:csv) { "N\n1\n2\n3\nx\ny\nz\n" }
      let(:column_mapping) { {"N" => maps_to("n", "integer")} }
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
  end

  describe "Result#to_h" do
    subject(:stored) { JSON.parse(JSON.generate(result.to_h)) }

    let(:result) do
      analyzer.call(
        path: csv_file("Age\n30\nx\n\n"),
        column_mapping: {"Age" => maps_to("age", "integer")}
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
            }
          }
        }
      )
    end
  end
end
