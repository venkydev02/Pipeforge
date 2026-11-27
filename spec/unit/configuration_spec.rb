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

    let(:kept_target) do
      loading
      described_class.target
    end

    def engine_file(engine)
      {"engine" => engine}.to_yaml
    end

    def file_message(*error_messages)
      argument_message(:settings_file_has_errors, path: described_class::DEFAULT_PATH, error_messages: error_messages)
    end

    def file_message_start(key, **arguments)
      /\A#{Regexp.escape(described_class::DEFAULT_PATH)}: #{Regexp.escape(argument_message(key, **arguments))}/
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

        it "keeps target as a TargetSettings with the adapter activerecord" do
          expect(kept_target).to eq(described_class::TargetSettings.new(adapter: "activerecord"))
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

    describe "target.adapter" do
      context "when target.adapter is activerecord" do
        let(:settings_file) { engine_file("target" => {"adapter" => "activerecord"}) }

        it "accepts it" do
          expect(kept_target.adapter).to eq("activerecord")
        end
      end

      context "when target.adapter is the name of a second adapter of the registry" do
        let(:settings_file) { engine_file("target" => {"adapter" => "spec_adapter"}) }

        before { add_spec_adapter }

        it "keeps that name" do
          expect(kept_target.adapter).to eq("spec_adapter")
        end
      end
    end

    describe "a value that is refused" do
      context "when execution.chunk_size is text" do
        let(:settings_file) { engine_file("execution" => {"chunk_size" => "5"}) }

        it "raises ArgumentError naming the setting and the value" do
          expect { loading }.to raise_error(
            ArgumentError, file_message(argument_message(:value_not_whole_number_at_least_1, name: "execution.chunk_size", value: "5"))
          )
        end
      end

      context "when recommendation.inclusion_threshold is 0" do
        let(:settings_file) { engine_file("recommendation" => {"inclusion_threshold" => 0}) }

        it "raises ArgumentError naming the setting and the value" do
          expect { loading }.to raise_error(
            ArgumentError, file_message(argument_message(:value_not_whole_number_at_least_1, name: "recommendation.inclusion_threshold", value: 0))
          )
        end
      end

      context "when recommendation.reorder_penalty is 101" do
        let(:settings_file) { engine_file("recommendation" => {"reorder_penalty" => 101}) }

        it "raises ArgumentError naming the setting and the value" do
          expect { loading }.to raise_error(
            ArgumentError, file_message(argument_message(:value_not_whole_number_from_0_to_100, name: "recommendation.reorder_penalty", value: 101))
          )
        end
      end

      context "when recommendation.reorder_penalty is negative" do
        let(:settings_file) { engine_file("recommendation" => {"reorder_penalty" => -1}) }

        it "raises ArgumentError naming the setting and the value" do
          expect { loading }.to raise_error(
            ArgumentError, file_message(argument_message(:value_not_whole_number_from_0_to_100, name: "recommendation.reorder_penalty", value: -1))
          )
        end
      end

      context "when recommendation.reorder_penalty is a decimal" do
        let(:settings_file) { engine_file("recommendation" => {"reorder_penalty" => 5.5}) }

        it "raises ArgumentError naming the setting and the value" do
          expect { loading }.to raise_error(
            ArgumentError, file_message(argument_message(:value_not_whole_number_from_0_to_100, name: "recommendation.reorder_penalty", value: 5.5))
          )
        end
      end

      context "when recommendation.reorder_penalty is text" do
        let(:settings_file) { engine_file("recommendation" => {"reorder_penalty" => "10"}) }

        it "raises ArgumentError naming the setting and the value" do
          expect { loading }.to raise_error(
            ArgumentError, file_message(argument_message(:value_not_whole_number_from_0_to_100, name: "recommendation.reorder_penalty", value: "10"))
          )
        end
      end
    end

    describe "an adapter that is refused" do
      context "when target.adapter is sequel, which is not registered" do
        let(:settings_file) { engine_file("target" => {"adapter" => "sequel"}) }

        it "raises ArgumentError naming the setting, the value and the adapters" do
          expect { loading }.to raise_error(
            ArgumentError,
            file_message(
              argument_message(:value_not_a_known_adapter, name: "target.adapter", value: "sequel", known_names: ["activerecord"])
            )
          )
        end
      end
    end

    describe "a settings file that cannot be used" do
      context "when the file is not valid YAML" do
        let(:settings_file) { "engine: [unclosed" }

        it "raises ArgumentError saying the file is not valid YAML" do
          expect { loading }.to raise_error(ArgumentError, file_message_start(:settings_not_valid_yaml, reason: ""))
        end
      end

      context "when the file has a YAML tag that is not allowed" do
        let(:settings_file) { "engine: !ruby/object:Object {}\n" }

        it "raises ArgumentError saying the file is not valid YAML" do
          expect { loading }.to raise_error(ArgumentError, file_message_start(:settings_not_valid_yaml, reason: ""))
        end
      end

      context "when the file is a list" do
        let(:settings_file) { [1, 2].to_yaml }

        it "raises ArgumentError saying it must be made of name: value entries" do
          expect { loading }.to raise_error(
            ArgumentError, file_message(argument_message(:settings_not_name_value_entries))
          )
        end
      end

      context "when engine is a list" do
        let(:settings_file) { engine_file(%w[execution recommendation]) }

        it "raises ArgumentError saying engine must hold sections" do
          expect { loading }.to raise_error(
            ArgumentError, file_message(argument_message(:settings_engine_not_sections))
          )
        end
      end
    end

    describe "a section or a setting that is not known" do
      context "when engine has a section it does not know" do
        let(:settings_file) { engine_file("source" => {"limit" => 3}) }

        it "raises ArgumentError naming the section" do
          expect { loading }.to raise_error(
            ArgumentError, file_message(argument_message(:settings_section_unknown, section_name: "source"))
          )
        end
      end

      context "when execution has a setting it does not know" do
        let(:settings_file) { engine_file("execution" => {"batch_size" => 3}) }

        it "raises ArgumentError naming the setting and the section" do
          expect { loading }.to raise_error(
            ArgumentError,
            file_message(argument_message(:settings_setting_unknown, setting_name: :batch_size, section_name: "execution"))
          )
        end
      end

      context "when target has a setting it does not know" do
        let(:settings_file) { engine_file("target" => {"database" => "contacts"}) }

        it "raises ArgumentError naming the setting and the section" do
          expect { loading }.to raise_error(
            ArgumentError,
            file_message(argument_message(:settings_setting_unknown, setting_name: :database, section_name: "target"))
          )
        end
      end

      context "when execution is a number" do
        let(:settings_file) { engine_file("execution" => 5) }

        it "raises ArgumentError saying the section must hold settings" do
          expect { loading }.to raise_error(
            ArgumentError, file_message(argument_message(:settings_section_not_settings, section_name: "execution"))
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
            file_message(
              argument_message(:settings_section_unknown, section_name: "source"),
              argument_message(:settings_setting_unknown, setting_name: :batch_size, section_name: "execution"),
              argument_message(:value_not_whole_number_at_least_1, name: "execution.chunk_size", value: 0)
            )
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
            file_message(
              argument_message(:value_not_whole_number_at_least_1, name: "execution.chunk_size", value: 0),
              argument_message(:value_not_whole_number_from_0_to_100, name: "recommendation.reorder_penalty", value: 101)
            )
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
            file_message(
              argument_message(:settings_section_not_settings, section_name: "execution"),
              argument_message(:value_not_whole_number_from_0_to_100, name: "recommendation.reorder_penalty", value: 101)
            )
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
            file_message(
              argument_message(:settings_setting_unknown, setting_name: :batch_size, section_name: "recommendation"),
              argument_message(:value_not_whole_number_from_0_to_100, name: "recommendation.reorder_penalty", value: 101)
            )
          )
        end
      end

      context "when target.adapter and execution.chunk_size are both wrong" do
        let(:settings_file) do
          engine_file("target" => {"adapter" => "sequel"}, "execution" => {"chunk_size" => 0})
        end

        it "reports both, execution.chunk_size first" do
          expect { loading }.to raise_error(
            ArgumentError,
            file_message(
              argument_message(:value_not_whole_number_at_least_1, name: "execution.chunk_size", value: 0),
              argument_message(:value_not_a_known_adapter, name: "target.adapter", value: "sequel", known_names: ["activerecord"])
            )
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

      context "when a load fails after a good load whose target.adapter is spec_adapter" do
        let(:settings_file) { engine_file("execution" => {"chunk_size" => 0}) }

        before do
          add_spec_adapter
          use_settings(target: {adapter: "spec_adapter"})
        end

        it "keeps target of the good load" do
          expect { loading }.to raise_error(ArgumentError)
          expect(described_class.target).to eq(described_class::TargetSettings.new(adapter: "spec_adapter"))
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

    describe "collaboration" do
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

      context "when target.adapter is activerecord" do
        let(:settings_file) { engine_file("target" => {"adapter" => "activerecord"}) }

        before do
          allow(Pipeforge::AdapterRegistry).to receive(:names).and_call_original
          allow(Pipeforge::AdapterRegistry).to receive(:resolve).and_call_original
          loading
        end

        it "asks AdapterRegistry.names" do
          expect(Pipeforge::AdapterRegistry).to have_received(:names)
        end

        it "does not resolve the adapter" do
          expect(Pipeforge::AdapterRegistry).not_to have_received(:resolve)
        end
      end
    end
  end
end
