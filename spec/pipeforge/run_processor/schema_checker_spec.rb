# frozen_string_literal: true

RSpec.describe Pipeforge::RunProcessor::SchemaChecker do
  subject(:checker) { described_class.new(target_schema: build_target_schema(columns: target_columns)) }

  let(:target_columns) { [build_target_column(name: "email")] }

  # The limits themselves are tested once, in the spec of ColumnLimitsChecker; here a column of each kind
  # shows that the checker asks it and turns what it finds into an entry.
  describe "#call" do
    subject(:errors) { checker.call(attributes: attributes) }

    let(:attributes) { {"email" => "ann@example.com"} }
    let(:codes) { errors.map { |error| error[:code] } }

    it "gives no error for a record that passes" do
      expect(errors).to eq([])
    end

    context "with a required column" do
      let(:target_columns) { [build_target_column(name: "email", required: true)] }

      context "when its value is empty" do
        let(:attributes) { {"email" => nil} }

        it "gives value_missing for that column" do
          expect(errors).to contain_exactly(include(code: :value_missing, target_column: "email"))
        end

        it "gives a message that a person can read" do
          expect(errors.first[:message]).to include("email")
        end

        it "gives the origin schema" do
          expect(errors.first[:origin]).to eq(:schema)
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

        it "gives value_too_long for that column, with a message that names it" do
          expect(errors).to contain_exactly(include(origin: :schema, code: :value_too_long, target_column: "code", message: /\Acode: /))
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
          expect(errors).to contain_exactly(include(code: :value_out_of_range, target_column: "age"))
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
      let(:target_columns) { [build_target_column(name: "hits", type: "integer", limit: 2, unsigned: true)] }

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
          expect(errors).to contain_exactly(include(code: :value_out_of_range, target_column: "fee"))
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
          expect(errors).to contain_exactly(include(code: :value_out_of_range, target_column: "ratio"))
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
        [build_target_column(name: "status", type: "integer", enum_values: {"draft" => 0, "placed" => 1})]
      end

      context "when the value is a label" do
        let(:attributes) { {"status" => "draft"} }

        it "gives no error" do
          expect(errors).to eq([])
        end
      end

      context "when the value is neither a label nor a stored value" do
        let(:attributes) { {"status" => "shipped"} }

        it "gives value_not_allowed for that column" do
          expect(errors).to contain_exactly(include(code: :value_not_allowed, target_column: "status"))
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
        expect(errors.map { |error| [error[:target_column], error[:code]] }).to eq(
          [["email", :value_missing], ["code", :value_too_long], ["age", :value_out_of_range]]
        )
      end
    end
  end
end
