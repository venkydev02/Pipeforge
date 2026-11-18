# frozen_string_literal: true

# HeaderAnalyzer builds its own matcher, pair scorer and tokenizer and reads its settings from
# Configuration, so they are doubles: Matcher.new, PairScorer.new and Tokenizer.new return doubles,
# Configuration.recommendation returns the settings of the context, and the matcher double answers
# the matcher result of the context. The target schema is plain data, built with the spec helpers.
#
# Each context gives the inputs. The contract group checks the calls; every other example expects
# the whole Result, built with result_of (the fields a context does not give keep their defaults).
#
# The groups follow what .call does, in order:
#   1. the contract: it builds the matcher from the settings and asks it to match;
#   2. the matches: one entry for each match of the matcher, with the fields of the match and the
#      metadata of its target column;
#   3. the unmatched columns: the same pieces for the source columns and the target columns;
#   4. the identity of the source and of the target.
RSpec.describe Pipeforge::HeaderAnalyzer do
  let(:matcher) { instance_double(Pipeforge::HeaderAnalyzer::Matcher) }
  let(:pair_scorer) { instance_double(Pipeforge::HeaderAnalyzer::PairScorer) }
  let(:tokenizer) { instance_double(Pipeforge::HeaderAnalyzer::Tokenizer) }
  let(:settings) { Pipeforge::Configuration::RecommendationSettings.new(inclusion_threshold: 55, reorder_penalty: 10) }

  let(:source_headers) { [] }
  let(:source_identifier) { "users.csv" }
  let(:target_columns) { [] }
  let(:table_name) { "users" }
  let(:model_name) { "User" }
  let(:schema) { build_target_schema(table_name: table_name, columns: target_columns, model_name: model_name) }
  let(:matcher_result) { matcher_result_of }
  let(:result) { call_header_analyzer }

  before do
    allow(Pipeforge::Configuration).to receive(:recommendation).and_return(settings)
    allow(Pipeforge::HeaderAnalyzer::PairScorer).to receive(:new).and_return(pair_scorer)
    allow(Pipeforge::HeaderAnalyzer::Tokenizer).to receive(:new).and_return(tokenizer)
    allow(Pipeforge::HeaderAnalyzer::Matcher).to receive(:new).and_return(matcher)
    allow(matcher).to receive(:call).and_return(matcher_result)
  end

  def call_header_analyzer
    described_class.call(source_headers: source_headers, source_identifier: source_identifier, target_schema: schema)
  end

  # What the matcher gives back.
  def matcher_result_of(matches: [], unmatched_source_column_names: [], unmatched_target_column_names: [])
    Pipeforge::HeaderAnalyzer::Matcher::Result.new(
      matches: matches,
      unmatched_source_column_names: unmatched_source_column_names,
      unmatched_target_column_names: unmatched_target_column_names
    )
  end

  def matcher_match(target:, source:, score:, tied_source_column_names: [])
    Pipeforge::HeaderAnalyzer::Matcher::Match.new(
      source_column_name: source, target_column_name: target, score: score, tied_source_column_names: tied_source_column_names
    )
  end

  # The Result that a context expects; the fields it does not give keep the defaults of the lets.
  def result_of(matches: [], unmatched_source_column_names: [], unmatched_target_columns: [],
    source_identifier: "users.csv", target_table_name: "users", model_name: "User")
    described_class::Result.new(
      source_identifier: source_identifier, target_table_name: target_table_name, model_name: model_name, matches: matches,
      unmatched_source_column_names: unmatched_source_column_names, unmatched_target_columns: unmatched_target_columns
    )
  end

  # The metadata of a target column that build_target_column filled with its defaults.
  def default_metadata(**overrides)
    {
      type: "string", sql_type: "varchar", limit: nil, is_signed: nil, max_length: nil, precision: nil, scale: nil,
      default: nil, enum_labels: nil, required: false, foreign_key: nil, polymorphic: nil
    }.merge(overrides)
  end

  describe ".call" do
    describe "the contract" do
      context "when the configuration has an inclusion threshold of 95 and a reorder penalty of 40" do
        let(:settings) do
          Pipeforge::Configuration::RecommendationSettings.new(inclusion_threshold: 95, reorder_penalty: 40)
        end

        before { call_header_analyzer }

        it "builds the matcher with that threshold, the pair scorer and the tokenizer" do
          expect(Pipeforge::HeaderAnalyzer::Matcher).to have_received(:new)
            .with(inclusion_threshold: 95, pair_scorer: pair_scorer, tokenizer: tokenizer)
        end

        it "builds the pair scorer with that penalty" do
          expect(Pipeforge::HeaderAnalyzer::PairScorer).to have_received(:new).with(reorder_penalty: 40)
        end
      end

      context "when it is given source headers and a target schema" do
        let(:source_headers) { ["First Name", "Last Name", "Zip"] }
        let(:target_columns) do
          [build_target_column(name: "first_name"), build_target_column(name: "last_name"),
            build_target_column(name: "company_id")]
        end

        before { call_header_analyzer }

        it "asks the matcher to match the headers, in file order, to the target column names, in table order" do
          expect(matcher).to have_received(:call).with(
            source_column_names: ["First Name", "Last Name", "Zip"], target_column_names: %w[first_name last_name company_id]
          )
        end
      end

      context "when there are no source headers" do
        let(:source_headers) { [] }
        let(:target_columns) { [build_target_column(name: "first_name")] }

        before { call_header_analyzer }

        it "asks the matcher to match no source columns" do
          expect(matcher).to have_received(:call).with(source_column_names: [], target_column_names: ["first_name"])
        end
      end

      context "when the schema has no columns" do
        let(:source_headers) { ["First Name"] }
        let(:target_columns) { [] }

        before { call_header_analyzer }

        it "asks the matcher to match the headers to no target columns" do
          expect(matcher).to have_received(:call).with(source_column_names: ["First Name"], target_column_names: [])
        end
      end
    end

    describe "the matches" do
      context "when the matcher matched two target columns" do
        let(:target_columns) do
          [build_target_column(name: "first_name", max_length: 50, required: true), build_target_column(name: "phone")]
        end
        let(:matcher_result) do
          matcher_result_of(
            matches: [
              matcher_match(target: "first_name", source: "First Name", score: 100.0),
              matcher_match(target: "phone", source: "Phone 1", score: 66.67, tied_source_column_names: ["Phone 2"])
            ]
          )
        end

        it "gives one entry for each match, in the order the matcher gave, with its fields and the metadata of its target column" do
          expect(result).to eq(
            result_of(
              matches: [
                {target_column_name: "first_name", source_column_name: "First Name", score: 100.0, tied_source_column_names: [],
                 metadata: default_metadata(max_length: 50, required: true)},
                {target_column_name: "phone", source_column_name: "Phone 1", score: 66.67, tied_source_column_names: ["Phone 2"],
                 metadata: default_metadata}
              ]
            )
          )
        end
      end
    end

    describe "the unmatched columns" do
      context "when the matcher left two source columns unmatched" do
        let(:matcher_result) { matcher_result_of(unmatched_source_column_names: %w[Zip Notes]) }

        it "lists them in the order the matcher gave" do
          expect(result).to eq(result_of(unmatched_source_column_names: %w[Zip Notes]))
        end
      end

      context "when a target column is the type column of a polymorphic association" do
        let(:target_columns) do
          [build_target_column(name: "commentable_type", polymorphic: build_polymorphic_column(association_name: "commentable", role: "type"))]
        end
        let(:matcher_result) { matcher_result_of(unmatched_target_column_names: %w[commentable_type]) }

        it "gives the polymorphic association and the role in the metadata of that column" do
          expect(result).to eq(
            result_of(
              unmatched_target_columns: [
                {
                  target_column_name: "commentable_type",
                  metadata: default_metadata(polymorphic: {association_name: "commentable", role: "type"})
                }
              ]
            )
          )
        end
      end

      context "when the matcher left two target columns unmatched" do
        let(:target_columns) do
          [
            build_target_column(
              name: "company_id", type: "integer", sql_type: "bigint", required: true,
              foreign_key: build_foreign_key(association_name: "company", parent_table_name: "companies")
            ),
            build_target_column(name: "notes")
          ]
        end
        let(:matcher_result) { matcher_result_of(unmatched_target_column_names: %w[company_id notes]) }

        it "gives one entry for each, in the order the matcher gave, with the metadata of its target column" do
          expect(result).to eq(
            result_of(
              unmatched_target_columns: [
                {
                  target_column_name: "company_id",
                  metadata: default_metadata(
                    type: "integer", sql_type: "bigint", required: true,
                    foreign_key: {association_name: "company", parent_table_name: "companies"}
                  )
                },
                {target_column_name: "notes", metadata: default_metadata}
              ]
            )
          )
        end
      end
    end

    describe "the identity of the source and of the target" do
      context "when the schema is of the table people with the model Person" do
        let(:table_name) { "people" }
        let(:model_name) { "Person" }

        it "names the table and the model" do
          expect(result).to eq(result_of(target_table_name: "people", model_name: "Person"))
        end
      end

      context "when the schema has no model" do
        let(:model_name) { nil }

        it "has no model" do
          expect(result).to eq(result_of(model_name: nil))
        end
      end

      context "when the source is people.csv" do
        let(:source_identifier) { "people.csv" }

        it "names the source with that identifier" do
          expect(result).to eq(result_of(source_identifier: "people.csv"))
        end
      end
    end
  end
end
