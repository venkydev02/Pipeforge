# frozen_string_literal: true

RSpec.describe Pipeforge::Configuration do
  describe ".load" do
    subject(:loading) { in_project_directory(config: settings_file) { described_class.load } }

    let(:default_execution) { described_class::ExecutionSettings.new(chunk_size: 2000) }
    let(:default_recommendation) do
      described_class::RecommendationSettings.new(inclusion_threshold: 55, reorder_penalty: 10)
    end
    let(:kept_settings) do
      loading
      {execution: described_class.execution, recommendation: described_class.recommendation}
    end

    def engine_file(engine)
      {"engine" => engine}.to_yaml
    end

    context "when the settings file has every known setting" do
      let(:settings_file) do
        engine_file(
          "execution" => {"chunk_size" => 300},
          "recommendation" => {"inclusion_threshold" => 70, "reorder_penalty" => 25}
        )
      end

      it "keeps execution as an ExecutionSettings and recommendation as a RecommendationSettings with the values of the file" do
        expect(kept_settings).to eq(
          execution: described_class::ExecutionSettings.new(chunk_size: 300),
          recommendation: described_class::RecommendationSettings.new(inclusion_threshold: 70, reorder_penalty: 25)
        )
      end
    end

    describe "settings that are not given" do
      let(:defaults) { {execution: default_execution, recommendation: default_recommendation} }

      context "when there is no settings file" do
        let(:settings_file) { nil }

        it "keeps the defaults" do
          expect(kept_settings).to eq(defaults)
        end
      end

      context "when the settings file is empty" do
        let(:settings_file) { "" }

        it "keeps the defaults" do
          expect(kept_settings).to eq(defaults)
        end
      end

      context "when the settings file has no engine section" do
        let(:settings_file) { {"version" => "1.0"}.to_yaml }

        it "keeps the defaults" do
          expect(kept_settings).to eq(defaults)
        end
      end

      context "when engine has nothing under it" do
        let(:settings_file) { engine_file(nil) }

        it "keeps the defaults" do
          expect(kept_settings).to eq(defaults)
        end
      end

      context "when execution has nothing under it" do
        let(:settings_file) do
          engine_file("execution" => nil, "recommendation" => {"reorder_penalty" => 20})
        end

        it "keeps the default of execution and the recommendation of the file" do
          expect(kept_settings).to eq(
            execution: default_execution,
            recommendation: described_class::RecommendationSettings.new(inclusion_threshold: 55, reorder_penalty: 20)
          )
        end
      end

      context "when the settings file has a top-level key other than engine" do
        let(:settings_file) do
          {"version" => "1.0", "engine" => {"execution" => {"chunk_size" => 40}}}.to_yaml
        end

        it "ignores that key" do
          expect(kept_settings).to eq(
            execution: described_class::ExecutionSettings.new(chunk_size: 40),
            recommendation: default_recommendation
          )
        end
      end

      context "when only execution.chunk_size is given" do
        let(:settings_file) { engine_file("execution" => {"chunk_size" => 40}) }

        it "reads it and keeps the defaults of recommendation" do
          expect(kept_settings).to eq(
            execution: described_class::ExecutionSettings.new(chunk_size: 40),
            recommendation: default_recommendation
          )
        end
      end

      context "when only recommendation.inclusion_threshold is given" do
        let(:settings_file) { engine_file("recommendation" => {"inclusion_threshold" => 80}) }

        it "reads it and keeps the default of reorder_penalty" do
          expect(kept_settings).to eq(
            execution: default_execution,
            recommendation: described_class::RecommendationSettings.new(inclusion_threshold: 80, reorder_penalty: 10)
          )
        end
      end
    end

    describe "values on the boundary" do
      context "when execution.chunk_size is 1" do
        let(:settings_file) { engine_file("execution" => {"chunk_size" => 1}) }

        it "accepts it" do
          expect(kept_settings[:execution]).to eq(described_class::ExecutionSettings.new(chunk_size: 1))
        end
      end

      context "when recommendation.inclusion_threshold is 1" do
        let(:settings_file) { engine_file("recommendation" => {"inclusion_threshold" => 1}) }

        it "accepts it" do
          expect(kept_settings[:recommendation]).to eq(
            described_class::RecommendationSettings.new(inclusion_threshold: 1, reorder_penalty: 10)
          )
        end
      end

      context "when recommendation.reorder_penalty is 0" do
        let(:settings_file) { engine_file("recommendation" => {"reorder_penalty" => 0}) }

        it "accepts it" do
          expect(kept_settings[:recommendation]).to eq(
            described_class::RecommendationSettings.new(inclusion_threshold: 55, reorder_penalty: 0)
          )
        end
      end

      context "when recommendation.reorder_penalty is 100" do
        let(:settings_file) { engine_file("recommendation" => {"reorder_penalty" => 100}) }

        it "accepts it" do
          expect(kept_settings[:recommendation]).to eq(
            described_class::RecommendationSettings.new(inclusion_threshold: 55, reorder_penalty: 100)
          )
        end
      end
    end

    describe "a value that is refused" do
      let(:chunk_size_sentence) { "must be a whole number of at least 1" }
      let(:reorder_penalty_sentence) { "must be a whole number from 0 to 100" }

      context "when execution.chunk_size is text" do
        let(:settings_file) { engine_file("execution" => {"chunk_size" => "5"}) }

        it "raises ArgumentError naming the setting and the value" do
          expect { loading }.to raise_error(
            ArgumentError, "config/pipeforge.yml: execution.chunk_size #{chunk_size_sentence}, got \"5\""
          )
        end
      end

      context "when execution.chunk_size is a decimal" do
        let(:settings_file) { engine_file("execution" => {"chunk_size" => 2.5}) }

        it "raises ArgumentError naming the setting and the value" do
          expect { loading }.to raise_error(
            ArgumentError, "config/pipeforge.yml: execution.chunk_size #{chunk_size_sentence}, got 2.5"
          )
        end
      end

      context "when execution.chunk_size is 0" do
        let(:settings_file) { engine_file("execution" => {"chunk_size" => 0}) }

        it "raises ArgumentError naming the setting and the value" do
          expect { loading }.to raise_error(
            ArgumentError, "config/pipeforge.yml: execution.chunk_size #{chunk_size_sentence}, got 0"
          )
        end
      end

      context "when execution.chunk_size is negative" do
        let(:settings_file) { engine_file("execution" => {"chunk_size" => -3}) }

        it "raises ArgumentError naming the setting and the value" do
          expect { loading }.to raise_error(
            ArgumentError, "config/pipeforge.yml: execution.chunk_size #{chunk_size_sentence}, got -3"
          )
        end
      end

      context "when execution.chunk_size is nil" do
        let(:settings_file) { engine_file("execution" => {"chunk_size" => nil}) }

        it "raises ArgumentError naming the setting and the value" do
          expect { loading }.to raise_error(
            ArgumentError, "config/pipeforge.yml: execution.chunk_size #{chunk_size_sentence}, got nil"
          )
        end
      end

      context "when recommendation.inclusion_threshold is 0" do
        let(:settings_file) { engine_file("recommendation" => {"inclusion_threshold" => 0}) }

        it "raises ArgumentError naming the setting and the value" do
          expect { loading }.to raise_error(
            ArgumentError, "config/pipeforge.yml: recommendation.inclusion_threshold #{chunk_size_sentence}, got 0"
          )
        end
      end

      context "when recommendation.reorder_penalty is 101" do
        let(:settings_file) { engine_file("recommendation" => {"reorder_penalty" => 101}) }

        it "raises ArgumentError naming the setting and the value" do
          expect { loading }.to raise_error(
            ArgumentError, "config/pipeforge.yml: recommendation.reorder_penalty #{reorder_penalty_sentence}, got 101"
          )
        end
      end

      context "when recommendation.reorder_penalty is negative" do
        let(:settings_file) { engine_file("recommendation" => {"reorder_penalty" => -1}) }

        it "raises ArgumentError naming the setting and the value" do
          expect { loading }.to raise_error(
            ArgumentError, "config/pipeforge.yml: recommendation.reorder_penalty #{reorder_penalty_sentence}, got -1"
          )
        end
      end

      context "when recommendation.reorder_penalty is a decimal" do
        let(:settings_file) { engine_file("recommendation" => {"reorder_penalty" => 5.5}) }

        it "raises ArgumentError naming the setting and the value" do
          expect { loading }.to raise_error(
            ArgumentError, "config/pipeforge.yml: recommendation.reorder_penalty #{reorder_penalty_sentence}, got 5.5"
          )
        end
      end

      context "when recommendation.reorder_penalty is text" do
        let(:settings_file) { engine_file("recommendation" => {"reorder_penalty" => "10"}) }

        it "raises ArgumentError naming the setting and the value" do
          expect { loading }.to raise_error(
            ArgumentError, "config/pipeforge.yml: recommendation.reorder_penalty #{reorder_penalty_sentence}, got \"10\""
          )
        end
      end
    end

    describe "a settings file that cannot be used" do
      context "when the file is not valid YAML" do
        let(:settings_file) { "engine: [unclosed" }

        it "raises ArgumentError saying the file is not valid YAML" do
          expect { loading }.to raise_error(ArgumentError, %r{\Aconfig/pipeforge\.yml: not valid YAML: })
        end
      end

      context "when the file has a YAML tag that is not allowed" do
        let(:settings_file) { "engine: !ruby/object:Object {}\n" }

        it "raises ArgumentError saying the file is not valid YAML" do
          expect { loading }.to raise_error(ArgumentError, %r{\Aconfig/pipeforge\.yml: not valid YAML: })
        end
      end

      context "when the file is a list" do
        let(:settings_file) { [1, 2].to_yaml }

        it "raises ArgumentError saying it must be made of name: value entries" do
          expect { loading }.to raise_error(
            ArgumentError, "config/pipeforge.yml: must be made of name: value entries at the top level"
          )
        end
      end

      context "when engine is a list" do
        let(:settings_file) { engine_file(%w[execution recommendation]) }

        it "raises ArgumentError saying engine must hold sections" do
          expect { loading }.to raise_error(
            ArgumentError,
            "config/pipeforge.yml: engine must hold sections, each written as a name with entries under it"
          )
        end
      end
    end

    describe "a section or a setting that is not known" do
      context "when engine has a section it does not know" do
        let(:settings_file) { engine_file("source" => {"limit" => 3}) }

        it "raises ArgumentError naming the section" do
          expect { loading }.to raise_error(ArgumentError, "config/pipeforge.yml: unknown section source")
        end
      end

      context "when execution has a setting it does not know" do
        let(:settings_file) { engine_file("execution" => {"batch_size" => 3}) }

        it "raises ArgumentError naming the setting and the section" do
          expect { loading }.to raise_error(
            ArgumentError, "config/pipeforge.yml: unknown setting batch_size in section execution"
          )
        end
      end

      context "when execution is a number" do
        let(:settings_file) { engine_file("execution" => 5) }

        it "raises ArgumentError saying the section must hold settings" do
          expect { loading }.to raise_error(
            ArgumentError,
            "config/pipeforge.yml: section execution must hold settings, each written as name: value"
          )
        end
      end
    end

    describe "several mistakes" do
      context "when execution.chunk_size is 0, execution has an unknown setting and there is an unknown section" do
        let(:settings_file) do
          engine_file("source" => {}, "execution" => {"chunk_size" => 0, "batch_size" => 3})
        end

        it "raises one ArgumentError that lists each mistake on its own line, in the order found" do
          expect { loading }.to raise_error(
            ArgumentError,
            <<~MESSAGE.chomp
              config/pipeforge.yml has 3 errors:
                - unknown section source
                - unknown setting batch_size in section execution
                - execution.chunk_size must be a whole number of at least 1, got 0
            MESSAGE
          )
        end
      end

      context "when execution.chunk_size and recommendation.reorder_penalty are both wrong" do
        let(:settings_file) do
          engine_file("execution" => {"chunk_size" => 0}, "recommendation" => {"reorder_penalty" => 101})
        end

        it "reports both" do
          expect { loading }.to raise_error(
            ArgumentError,
            <<~MESSAGE.chomp
              config/pipeforge.yml has 2 errors:
                - execution.chunk_size must be a whole number of at least 1, got 0
                - recommendation.reorder_penalty must be a whole number from 0 to 100, got 101
            MESSAGE
          )
        end
      end

      context "when execution is a number and recommendation.reorder_penalty is wrong" do
        let(:settings_file) do
          engine_file("execution" => 5, "recommendation" => {"reorder_penalty" => 101})
        end

        it "reports the wrong value as well" do
          expect { loading }.to raise_error(
            ArgumentError,
            <<~MESSAGE.chomp
              config/pipeforge.yml has 2 errors:
                - section execution must hold settings, each written as name: value
                - recommendation.reorder_penalty must be a whole number from 0 to 100, got 101
            MESSAGE
          )
        end
      end

      context "when recommendation has an unknown setting and a wrong reorder_penalty" do
        let(:settings_file) do
          engine_file("recommendation" => {"batch_size" => 3, "reorder_penalty" => 101})
        end

        it "reports both" do
          expect { loading }.to raise_error(
            ArgumentError,
            <<~MESSAGE.chomp
              config/pipeforge.yml has 2 errors:
                - unknown setting batch_size in section recommendation
                - recommendation.reorder_penalty must be a whole number from 0 to 100, got 101
            MESSAGE
          )
        end
      end
    end

    describe "settings kept from an earlier load" do
      context "when a load fails after a good load" do
        let(:settings_file) { engine_file("execution" => {"chunk_size" => 0}) }

        before do
          use_settings(execution: {chunk_size: 7}, recommendation: {reorder_penalty: 30})
        end

        it "raises ArgumentError and keeps the settings of the good load" do
          expect { loading }.to raise_error(ArgumentError)
          expect({execution: described_class.execution, recommendation: described_class.recommendation}).to eq(
            execution: described_class::ExecutionSettings.new(chunk_size: 7),
            recommendation: described_class::RecommendationSettings.new(inclusion_threshold: 55, reorder_penalty: 30)
          )
        end
      end

      context "when a second good load has other values" do
        let(:settings_file) { engine_file("execution" => {"chunk_size" => 9}) }

        before do
          use_settings(execution: {chunk_size: 7}, recommendation: {reorder_penalty: 30})
        end

        it "replaces the settings of the first load" do
          expect(kept_settings).to eq(
            execution: described_class::ExecutionSettings.new(chunk_size: 9),
            recommendation: default_recommendation
          )
        end
      end
    end

    describe "collaboration with Utilities" do
      before do
        allow(Pipeforge::Utilities).to receive(:positive_whole_number?).and_call_original
      end

      context "when execution.chunk_size is 5" do
        let(:settings_file) { engine_file("execution" => {"chunk_size" => 5}) }

        it "asks Utilities.positive_whole_number? with value 5 and keeps the setting" do
          expect(kept_settings[:execution]).to eq(described_class::ExecutionSettings.new(chunk_size: 5))
          expect(Pipeforge::Utilities).to have_received(:positive_whole_number?).with(value: 5)
        end
      end

      context "when recommendation.inclusion_threshold is 7" do
        let(:settings_file) { engine_file("recommendation" => {"inclusion_threshold" => 7}) }

        it "asks Utilities.positive_whole_number? with value 7 and keeps the setting" do
          expect(kept_settings[:recommendation]).to eq(
            described_class::RecommendationSettings.new(inclusion_threshold: 7, reorder_penalty: 10)
          )
          expect(Pipeforge::Utilities).to have_received(:positive_whole_number?).with(value: 7)
        end
      end
    end
  end
end
