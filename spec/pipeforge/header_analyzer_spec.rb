# frozen_string_literal: true

RSpec.describe Pipeforge::HeaderAnalyzer do
  let(:settings) { {} }

  # The parts of the engine read their settings from Configuration.
  before { use_settings(settings) }
  let(:source_headers) { ["First Name", "Last Name", "Zip"] }
  let(:source_identifier) { "users.csv" }
  let(:foreign_key) { build_foreign_key(association: "company", parent_table: "companies") }
  let(:target_columns) do
    [
      build_target_column(name: "first_name", max_length: 50, required: true),
      build_target_column(name: "last_name"),
      build_target_column(name: "company_id", type: "integer", sql_type: "bigint", required: true, foreign_key: foreign_key)
    ]
  end
  let(:schema) { build_target_schema(columns: target_columns) }

  # The metadata of a target column that build_target_column filled with its defaults.
  def default_metadata(**overrides)
    {
      type: "string", sql_type: "varchar", limit: nil, unsigned: false, max_length: nil, precision: nil, scale: nil,
      default: nil, enum_values: nil, required: false, foreign_key: nil
    }.merge(overrides)
  end

  describe ".call" do
    subject(:result) do
      described_class.call(
        source_headers: source_headers, source_identifier: source_identifier, target_schema: schema
      )
    end

    # The match of a target column in the result.
    def match_for(target_column)
      result.matches.find { |match| match[:target_column] == target_column }
    end

    it "keys the matches by target column, in table order" do
      expect(result.matches.map { |match| match[:target_column] }).to eq(%w[first_name last_name])
    end

    it "gives each match its source column and score" do
      expect(match_for("first_name")).to include(source_column: "First Name", score: 100.0)
      expect(match_for("last_name")).to include(source_column: "Last Name", score: 100.0)
    end

    it "has an empty tied_with when nothing tied" do
      expect(match_for("first_name")[:tied_with]).to eq([])
    end

    it "gives each match the metadata of its target column" do
      expect(match_for("first_name")[:metadata]).to eq(default_metadata(max_length: 50, required: true))
    end

    context "with an enum column" do
      let(:source_headers) { ["Status"] }
      let(:target_columns) do
        [build_target_column(name: "status", type: "integer", default: "draft", enum_values: {"draft" => 0, "placed" => 1})]
      end

      it "gives the labels and stored values of the enum in its metadata" do
        expect(match_for("status")[:metadata]).to include(default: "draft", enum_values: {"draft" => 0, "placed" => 1})
      end
    end

    it "lists the source columns without a match" do
      expect(result.unmatched_source_columns).to eq(%w[Zip])
    end

    it "lists the target columns without a match, each with its metadata" do
      expect(result.unmatched_target_columns).to eq(
        [
          {
            target_column: "company_id",
            metadata: default_metadata(
              type: "integer", sql_type: "bigint", required: true,
              foreign_key: {association: "company", parent_table: "companies"}
            )
          }
        ]
      )
    end

    it "names the table and the model" do
      expect(result).to have_attributes(target_table: "users", model: "User")
    end

    it "names the source with the identifier it was given" do
      expect(result.source_identifier).to eq("users.csv")
    end

    it "gives plain JSON types that survive a round trip" do
      expect(JSON.parse(JSON.generate(result.to_h))).to eq(
        "source_identifier" => "users.csv",
        "target_table" => "users",
        "model" => "User",
        "matches" => [
          {
            "target_column" => "first_name", "source_column" => "First Name", "score" => 100.0, "tied_with" => [],
            "metadata" => {
              "type" => "string", "sql_type" => "varchar", "limit" => nil, "unsigned" => false, "max_length" => 50,
              "precision" => nil, "scale" => nil, "default" => nil, "enum_values" => nil, "required" => true,
              "foreign_key" => nil
            }
          },
          {
            "target_column" => "last_name", "source_column" => "Last Name", "score" => 100.0, "tied_with" => [],
            "metadata" => {
              "type" => "string", "sql_type" => "varchar", "limit" => nil, "unsigned" => false, "max_length" => nil,
              "precision" => nil, "scale" => nil, "default" => nil, "enum_values" => nil, "required" => false,
              "foreign_key" => nil
            }
          }
        ],
        "unmatched_source_columns" => %w[Zip],
        "unmatched_target_columns" => [
          {
            "target_column" => "company_id",
            "metadata" => {
              "type" => "integer", "sql_type" => "bigint", "limit" => nil, "unsigned" => false, "max_length" => nil,
              "precision" => nil, "scale" => nil, "default" => nil, "enum_values" => nil, "required" => true,
              "foreign_key" => {"association" => "company", "parent_table" => "companies"}
            }
          }
        ]
      )
    end

    context "when two source columns tie for one target" do
      let(:source_headers) { ["Phone 2", "Phone 1"] }
      let(:target_columns) { [build_target_column(name: "phone")] }

      it "matches the source column whose name comes first" do
        expect(match_for("phone")).to include(source_column: "Phone 1", score: 66.67)
      end

      it "lists the other one in tied_with" do
        expect(match_for("phone")[:tied_with]).to eq(["Phone 2"])
      end

      it "still lists it among the unmatched source columns" do
        expect(result.unmatched_source_columns).to eq(["Phone 2"])
      end
    end

    context "when a source column fits several targets with the same score" do
      let(:source_headers) { ["Name"] }
      let(:target_columns) { [build_target_column(name: "last_name"), build_target_column(name: "full_name")] }

      it "puts the source column in each of their entries" do
        expect(result.matches.map { |match| [match[:target_column], match[:source_column]] }).to eq(
          [["last_name", "Name"], ["full_name", "Name"]]
        )
      end

      it "does not list it among the unmatched source columns" do
        expect(result.unmatched_source_columns).to be_empty
      end
    end

    context "when no column matches" do
      let(:source_headers) { ["Zip"] }

      it "has no matches and lists every column as unmatched" do
        expect(result.matches).to eq([])
        expect(result.unmatched_source_columns).to eq(%w[Zip])
        expect(result.unmatched_target_columns.map { |target| target[:target_column] }).to eq(%w[first_name last_name company_id])
      end
    end

    context "with settings in the configuration" do
      let(:source_headers) { ["Name First"] }
      let(:target_columns) { [build_target_column(name: "first_name")] }

      context "with the default reorder penalty" do
        it "takes 10 points off a reordered match" do
          expect(match_for("first_name")[:score]).to eq(90.0)
        end
      end

      context "with a larger reorder penalty" do
        let(:settings) { {recommendation: {reorder_penalty: 40}} }

        it "takes that many points off, and the match stays when it still reaches the threshold" do
          expect(match_for("first_name")[:score]).to eq(60.0)
        end
      end

      context "with a higher inclusion threshold" do
        let(:settings) { {recommendation: {inclusion_threshold: 95}} }

        it "leaves the pair unmatched" do
          expect(result.matches).to eq([])
          expect(result.unmatched_source_columns).to eq(["Name First"])
        end
      end
    end
  end
end
