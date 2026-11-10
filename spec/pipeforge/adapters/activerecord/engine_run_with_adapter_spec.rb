# frozen_string_literal: true

# The core's run found and used the ActiveRecord adapter, end to end, against an in-memory database.
RSpec.describe Pipeforge::Engine, "#run with the ActiveRecord adapter installed" do
  subject(:run_result) do
    engine.run(mode: :dry_run, mapped_columns: mapped_columns) { |chunk_result| chunk_results << chunk_result }
  end

  let(:engine) { described_class.new(source_io: csv_io(csv), target_model: "AdapterSpecModels::Membership") }
  let(:company) { AdapterSpecModels::Company.create!(name: "Acme") }
  let(:chunk_results) { [] }
  let(:failed_rows) { chunk_results.flat_map(&:failed_rows) }
  # One row for each kind of mistake, 10 rows in all, read in chunks of 5.
  let(:csv) do
    <<~CSV
      Email,Seats,Fee,Tier,Company
      ann@example.com,10,10.50,basic,#{company.id}
      ,10,10.50,basic,#{company.id}
      bob@example.com,40000,1.00,basic,#{company.id}
      carl@example.com,5,10000.00,pro,#{company.id}
      dup@example.com,5,1.00,pro,#{company.id}
      eve@example.com,5,1.00,gold,#{company.id}
      fay@example.com,5,1.00,pro,999999
      averyveryveryverylongemail@example.com,5,1.00,pro,#{company.id}
      gus@example.com,7,1.00,1,#{company.id}
      hal@example.com,5,999.999,pro,#{company.id}
    CSV
  end
  let(:mapped_columns) do
    {
      "email" => {source_column: "Email"}, "seats" => {source_column: "Seats"}, "fee" => {source_column: "Fee"},
      "tier" => {source_column: "Tier"}, "company_id" => {source_column: "Company"}
    }
  end

  # The codes of the failed row with that row number, in order.
  def codes_of_row(row_number)
    failed_rows.find { |failed_row| failed_row.row_number == row_number }.errors.map { |error| error[:code] }
  end

  before do
    use_settings(execution: {chunk_size: 5})
    AdapterSpecModels::Membership.create!(email: "dup@example.com", tier: :basic, company: company)
  end

  it "counts the rows that would load and the rows that would not" do
    expect(run_result).to have_attributes(processed_rows_count: 10, valid_rows_count: 2, failed_rows_count: 8)
  end

  it "reports exactly the rows with a mistake, by their row number in the file" do
    run_result

    expect(failed_rows.map(&:row_number)).to eq([2, 3, 4, 5, 6, 7, 8, 10])
  end

  it "reports a decimal that the cast rounds up to too many digits before the point" do
    run_result

    expect(codes_of_row(10)).to eq([:value_out_of_range])
  end

  it "reports a missing required value once, although the model and the schema both find it" do
    run_result

    expect(codes_of_row(2)).to eq([:value_missing])
  end

  it "reports a number too big for its column, which the model does not check" do
    run_result

    expect(codes_of_row(3)).to eq([:value_out_of_range])
  end

  it "reports a decimal with too many digits before the point" do
    run_result

    expect(codes_of_row(4)).to eq([:value_out_of_range])
  end

  it "reports a value the table already has" do
    run_result

    expect(codes_of_row(5)).to eq([:value_not_unique])
  end

  it "reports an enum label that is not one of the model's, once" do
    run_result

    expect(codes_of_row(6)).to eq([:value_not_allowed])
  end

  it "reports a parent that does not exist, on the foreign key column" do
    run_result

    expect(failed_rows.find { |failed_row| failed_row.row_number == 7 }.errors).to contain_exactly(
      include(origin: :model, code: :parent_missing, target_column: "company_id")
    )
  end

  it "reports a too long value once, although the model and the schema both find it" do
    run_result

    expect(codes_of_row(8)).to eq([:value_too_long])
  end

  it "accepts a stored enum value written as text" do
    run_result

    expect(failed_rows.map(&:row_number)).not_to include(9)
  end

  it "shows the values as they would have been loaded, keyed by target column" do
    run_result

    expect(failed_rows.first.mapped_values).to eq(
      "email" => nil, "seats" => "10", "fee" => "10.50", "tier" => "basic", "company_id" => company.id.to_s
    )
  end

  it "asks for the parents once for each chunk" do
    queries = []
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |_name, _start, _finish, _id, payload|
      queries << payload[:sql] if payload[:name] != "SCHEMA" && payload[:sql].include?('FROM "companies"')
    end

    run_result
    ActiveSupport::Notifications.unsubscribe(subscriber)

    expect(queries.size).to eq(2)
  end

  it "writes no row to the table" do
    expect { run_result }.not_to change(AdapterSpecModels::Membership, :count)
  end

  it "gives the same result when the rows are read again" do
    first_result = engine.run(mode: :dry_run, mapped_columns: mapped_columns)

    expect(engine.run(mode: :run, mapped_columns: mapped_columns)).to eq(first_result)
  end
end

# The run checks an unsigned integer attribute against its own range.
RSpec.describe Pipeforge::Engine, "#run with an unsigned integer attribute" do
  subject(:run_result) do
    engine.run(mode: :dry_run, mapped_columns: mapped_columns) { |chunk_result| chunk_results << chunk_result }
  end

  let(:engine) { described_class.new(source_io: csv_io(csv), target_model: "AdapterSpecModels::Counter") }
  let(:chunk_results) { [] }
  let(:failed_rows) { chunk_results.flat_map(&:failed_rows) }
  let(:csv) { "Hits,Misses\n40000,1\n65535,1\n65536,1\n-1,1\n0,40000\n" }
  let(:mapped_columns) do
    {"hits" => {source_column: "Hits"}, "misses" => {source_column: "Misses"}}
  end

  it "accepts a value above the signed range but within the unsigned one" do
    run_result

    expect(failed_rows.map(&:row_number)).not_to include(1, 2)
  end

  it "reports a value past the unsigned range, and a negative one" do
    run_result

    expect(failed_rows.map { |failed_row| [failed_row.row_number, failed_row.errors.map { |error| error[:code] }] }).to eq(
      [[3, [:value_out_of_range]], [4, [:value_out_of_range]], [5, [:value_out_of_range]]]
    )
  end

  it "keeps the signed range for the other column of the table" do
    run_result

    expect(failed_rows.last.errors.first).to include(target_column: "misses", code: :value_out_of_range)
  end
end

# The run checks a float against the largest number its column holds, the size read from the model.
RSpec.describe Pipeforge::Engine, "#run with float columns" do
  subject(:run_result) do
    engine.run(mode: :dry_run, mapped_columns: mapped_columns) { |chunk_result| chunk_results << chunk_result }
  end

  let(:engine) { described_class.new(source_io: csv_io(csv), target_model: "AdapterSpecModels::Measurement") }
  let(:chunk_results) { [] }
  let(:failed_rows) { chunk_results.flat_map(&:failed_rows) }
  let(:csv) { "Ratio,Weight\n1.5,1.5\n1e50,1e50\n1e39,1e9999\n3.4e38,1.7e308\n" }
  let(:mapped_columns) do
    {"ratio" => {source_column: "Ratio"}, "weight" => {source_column: "Weight"}}
  end

  def errors_of_row(row_number)
    failed_rows.find { |failed_row| failed_row.row_number == row_number }.errors.map do |error|
      [error[:target_column], error[:code]]
    end
  end

  it "reports a number past a single precision column although a double precision column holds it" do
    run_result

    expect(errors_of_row(2)).to eq([["ratio", :value_out_of_range]])
  end

  it "reports a text that is read as infinity, and a number past single precision, each on its column" do
    run_result

    expect(errors_of_row(3)).to contain_exactly(["ratio", :value_out_of_range], ["weight", :value_out_of_range])
  end

  it "accepts the largest values each column holds" do
    run_result

    expect(failed_rows.map(&:row_number)).to eq([2, 3])
  end
end
