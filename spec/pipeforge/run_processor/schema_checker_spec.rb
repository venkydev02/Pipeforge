# frozen_string_literal: true

RSpec.describe Pipeforge::RunProcessor::SchemaChecker do
  subject(:checker) { described_class.new(resolved_mapped_columns: resolved_mapped_columns) }

  let(:target_columns) { [build_target_column(name: "email")] }
  # The columns of the table that an entry fills; the others are not mapped.
  let(:mapped_target_columns) { target_columns }
  let(:resolved_mapped_columns) do
    mapped_target_columns.to_h do |target_column|
      [
        target_column.name,
        Pipeforge::ResolvedMappedColumn.new(
          source_column_name: target_column.name, value_mapping: {}, target_column: target_column
        )
      ]
    end
  end

  # The limits themselves are tested once, in the spec of ColumnLimitsChecker; here a column of each kind
  # shows that the checker asks it and gives what it finds as an entry with the origin and the value. The entry is
  # compared with the one the ErrorCatalog builds for the same mistake.
  describe "#call" do
    subject(:errors) { checker.call(attributes: attributes) }

    let(:attributes) { {"email" => "ann@example.com"} }
    let(:codes) { errors.map { |error| error[:code] } }

    def catalog_error(key, **facts)
      Pipeforge::ErrorCatalog::ERRORS.fetch(key).call(**facts)
    end

    it "gives no error for a record that passes" do
      expect(errors).to eq([])
    end

    context "with a required column" do
      let(:target_columns) { [build_target_column(name: "email", required: true)] }

      context "when its value is empty" do
        let(:attributes) { {"email" => nil} }

        it "gives value_missing for that column, with the origin schema and no value" do
          expect(errors).to eq(
            [catalog_error(:value_missing, origin: :schema, target_column_name: "email", value: nil)]
          )
        end
      end

      context "when it is left out of the attributes" do
        let(:attributes) { {} }

        it "gives value_missing" do
          expect(codes).to eq([:value_missing])
        end
      end

      context "when it has a value" do
        it "gives no error" do
          expect(errors).to eq([])
        end
      end
    end

    context "with a column that is not required and has no value" do
      let(:attributes) { {"email" => nil} }

      it "gives no error" do
        expect(errors).to eq([])
      end
    end

    context "with a string column that has a maximum length" do
      let(:target_columns) { [build_target_column(name: "code", type: "string", max_length: 3)] }

      context "when the value is longer" do
        let(:attributes) { {"code" => "abcd"} }

        it "gives value_too_long for that column, with the origin schema and the value that failed" do
          expect(errors).to eq(
            [
              catalog_error(
                :value_too_long, origin: :schema, target_column_name: "code", value: "abcd", length: 4, max_length: 3
              )
            ]
          )
        end
      end

      context "when the value is exactly as long" do
        let(:attributes) { {"code" => "abc"} }

        it "gives no error" do
          expect(errors).to eq([])
        end
      end
    end

    context "with an integer column of 2 bytes" do
      let(:target_columns) { [build_target_column(name: "age", type: "integer", limit: 2)] }

      context "when the value is one more than fits" do
        let(:attributes) { {"age" => 32_768} }

        it "gives value_out_of_range for that column" do
          expect(errors).to contain_exactly(include(code: :value_out_of_range, target_column_name: "age"))
        end
      end

      context "when the value fits" do
        let(:attributes) { {"age" => 32_767} }

        it "gives no error" do
          expect(errors).to eq([])
        end
      end
    end

    context "with an unsigned integer column of 2 bytes" do
      let(:target_columns) { [build_target_column(name: "hits", type: "integer", limit: 2, is_signed: false)] }

      it "accepts a value above the signed range" do
        expect(checker.call(attributes: {"hits" => 65_535})).to eq([])
      end

      it "rejects a negative value" do
        expect(checker.call(attributes: {"hits" => -1}).map { |error| error[:code] }).to eq([:value_out_of_range])
      end
    end

    context "with a decimal column of precision 5 and scale 2" do
      let(:target_columns) { [build_target_column(name: "fee", type: "decimal", precision: 5, scale: 2)] }

      context "when the value has 4 digits before the point" do
        let(:attributes) { {"fee" => BigDecimal("1000.00")} }

        it "gives value_out_of_range for that column" do
          expect(errors).to contain_exactly(include(code: :value_out_of_range, target_column_name: "fee"))
        end
      end

      context "when rounding to the scale adds a digit before the point" do
        let(:attributes) { {"fee" => 999.999} }

        it "gives value_out_of_range, because the database stores 1000.00" do
          expect(codes).to eq([:value_out_of_range])
        end
      end

      context "when the value fits" do
        let(:attributes) { {"fee" => BigDecimal("999.99")} }

        it "gives no error" do
          expect(errors).to eq([])
        end
      end
    end

    context "with a float column of single precision" do
      let(:target_columns) { [build_target_column(name: "ratio", type: "float", limit: 24)] }

      context "when the value is past the range" do
        let(:attributes) { {"ratio" => 3.5e38} }

        it "gives value_out_of_range for that column" do
          expect(errors).to contain_exactly(include(code: :value_out_of_range, target_column_name: "ratio"))
        end
      end

      context "when the value has been cast to infinity" do
        let(:attributes) { {"ratio" => Float::INFINITY} }

        it "gives value_out_of_range" do
          expect(codes).to eq([:value_out_of_range])
        end
      end
    end

    context "with an enum column" do
      let(:target_columns) do
        [build_target_column(name: "status", type: "integer", enum_labels: %w[draft placed])]
      end

      context "when the value is a label" do
        let(:attributes) { {"status" => "draft"} }

        it "gives no error" do
          expect(errors).to eq([])
        end
      end

      context "when the value is not a label" do
        let(:attributes) { {"status" => "shipped"} }

        it "gives value_not_allowed for that column" do
          expect(errors).to contain_exactly(include(code: :value_not_allowed, target_column_name: "status"))
        end
      end
    end

    context "with a column of a type that has no limit" do
      let(:target_columns) { [build_target_column(name: "active", type: "boolean")] }
      let(:attributes) { {"active" => true} }

      it "gives no error" do
        expect(errors).to eq([])
      end
    end

    context "with mistakes in several columns" do
      let(:target_columns) do
        [
          build_target_column(name: "email", required: true),
          build_target_column(name: "code", type: "string", max_length: 1),
          build_target_column(name: "age", type: "integer", limit: 1)
        ]
      end
      let(:attributes) { {"email" => nil, "code" => "ab", "age" => 200} }

      it "gives one entry for each, in column order" do
        expect(errors.map { |error| [error[:target_column_name], error[:code]] }).to eq(
          [["email", :value_missing], ["code", :value_too_long], ["age", :value_out_of_range]]
        )
      end
    end
  end

  describe "a column of the table that is not mapped" do
    subject(:errors) { checker.call(attributes: {"email" => "ann@example.com", "note" => nil}) }

    let(:target_columns) { [build_target_column(name: "email"), build_target_column(name: "note", required: true)] }
    let(:mapped_target_columns) { [target_columns.first] }

    it "is not checked: the model and the database check it" do
      expect(errors).to eq([])
    end
  end
end
