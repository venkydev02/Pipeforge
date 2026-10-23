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
      build_target_column(name: "first_name", max_length: 50, nullable: false),
      build_target_column(name: "last_name"),
      build_target_column(name: "company_id", type: "integer", sql_type: "bigint", foreign_key: foreign_key)
    ]
  end
  let(:schema) { build_target_schema(columns: target_columns) }

  # The metadata of a target column that build_target_column filled with its defaults.
  def default_metadata(**overrides)
    {
      type: "string", sql_type: "varchar", limit: nil, max_length: nil, precision: nil, scale: nil,
      nullable: true, default: nil, foreign_key: nil
    }.merge(overrides)
  end

  describe ".call" do
    subject(:result) do
      described_class.call(
        source_headers: source_headers, source_identifier: source_identifier, target_schema: schema
      )
    end

    it "keys the matches by target column, in table order" do
      expect(result.matches.keys).to eq(%w[first_name last_name])
    end

    it "gives each match its source column and score" do
      expect(result.matches["first_name"]).to include(source_column: "First Name", score: 100.0)
      expect(result.matches["last_name"]).to include(source_column: "Last Name", score: 100.0)
    end

    it "gives each match the metadata of its target column" do
      expect(result.matches["first_name"][:metadata]).to eq(default_metadata(max_length: 50, nullable: false))
    end

    it "lists the source columns without a match" do
      expect(result.unmatched_source_columns).to eq(%w[Zip])
    end

    it "lists the target columns without a match, each with its metadata" do
      expect(result.unmatched_target_columns).to eq(
        [
          {
            name: "company_id",
            metadata: default_metadata(
              type: "integer", sql_type: "bigint",
              foreign_key: {association: "company", parent_table: "companies", required: true}
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
        "matches" => {
          "first_name" => {
            "source_column" => "First Name", "score" => 100.0,
            "metadata" => {
              "type" => "string", "sql_type" => "varchar", "limit" => nil, "max_length" => 50,
              "precision" => nil, "scale" => nil, "nullable" => false, "default" => nil, "foreign_key" => nil
            }
          },
          "last_name" => {
            "source_column" => "Last Name", "score" => 100.0,
            "metadata" => {
              "type" => "string", "sql_type" => "varchar", "limit" => nil, "max_length" => nil,
              "precision" => nil, "scale" => nil, "nullable" => true, "default" => nil, "foreign_key" => nil
            }
          }
        },
        "unmatched_source_columns" => %w[Zip],
        "unmatched_target_columns" => [
          {
            "name" => "company_id",
            "metadata" => {
              "type" => "integer", "sql_type" => "bigint", "limit" => nil, "max_length" => nil,
              "precision" => nil, "scale" => nil, "nullable" => true, "default" => nil,
              "foreign_key" => {"association" => "company", "parent_table" => "companies", "required" => true}
            }
          }
        ]
      )
    end

    context "when a source column fits several targets with the same score" do
      let(:source_headers) { ["Name"] }
      let(:target_columns) { [build_target_column(name: "last_name"), build_target_column(name: "full_name")] }

      it "puts the source column in each of their entries" do
        expect(result.matches.transform_values { |match| match[:source_column] }).to eq(
          "last_name" => "Name", "full_name" => "Name"
        )
      end

      it "does not list it among the unmatched source columns" do
        expect(result.unmatched_source_columns).to be_empty
      end
    end

    context "when no column matches" do
      let(:source_headers) { ["Zip"] }

      it "has no matches and lists every column as unmatched" do
        expect(result.matches).to eq({})
        expect(result.unmatched_source_columns).to eq(%w[Zip])
        expect(result.unmatched_target_columns.map { |target| target[:name] }).to eq(%w[first_name last_name company_id])
      end
    end

    context "with settings in the configuration" do
      let(:source_headers) { ["Name First"] }
      let(:target_columns) { [build_target_column(name: "first_name")] }

      context "with the default reorder penalty" do
        it "takes 10 points off a reordered match" do
          expect(result.matches["first_name"][:score]).to eq(90.0)
        end
      end

      context "with a larger reorder penalty" do
        let(:settings) { {recommendation: {reorder_penalty: 40}} }

        it "takes that many points off, and the match stays when it still reaches the threshold" do
          expect(result.matches["first_name"][:score]).to eq(60.0)
        end
      end

      context "with a higher inclusion threshold" do
        let(:settings) { {recommendation: {inclusion_threshold: 95}} }

        it "leaves the pair unmatched" do
          expect(result.matches).to eq({})
          expect(result.unmatched_source_columns).to eq(["Name First"])
        end
      end
    end
  end
end
