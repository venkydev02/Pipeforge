# frozen_string_literal: true

RSpec.describe Pipeforge::Source::ReusableIO do
  subject(:source_io) { described_class.new(io: io) }

  let(:io) { StringIO.new("A,B\n1,2\n") }

  describe ".new" do
    it "accepts an IO that can be read, rewound and seeked" do
      expect { source_io }.not_to raise_error
    end

    context "when the IO has none of the methods the engine needs" do
      let(:io) { Object.new }

      it "stops with our own error, listing every missing method" do
        expect { source_io }.to raise_error(
          Pipeforge::Source::UnsupportedSourceError, /read.*rewind.*seek/
        )
      end

      it "gives a code for each missing method" do
        expect { source_io }.to raise_error(Pipeforge::Source::UnsupportedSourceError) do |error|
          expect(error.codes).to eq(%i[source_io_missing_read source_io_missing_rewind source_io_missing_seek])
        end
      end
    end

    context "when the IO lacks only seek" do
      let(:io) { instance_double(IO, read: nil, rewind: 0) }

      it "reports just that method" do
        expect { source_io }.to raise_error(Pipeforge::Source::UnsupportedSourceError) do |error|
          expect(error.errors.map { |entry| entry.slice(:code, :method) }).to eq(
            [{code: :source_io_missing_seek, method: :seek}]
          )
        end
      end
    end
  end

  describe "reading" do
    it "reads a line" do
      expect(source_io.gets("\n")).to eq("A,B\n")
    end

    it "reads bytes" do
      expect(source_io.read(3)).to eq("A,B")
    end

    it "tells when the end is reached" do
      source_io.read

      expect(source_io.eof?).to be(true)
    end

    it "starts again from the top after a rewind" do
      source_io.read
      source_io.rewind

      expect(source_io.gets("\n")).to eq("A,B\n")
    end

    it "reports the encoding of the IO" do
      expect(source_io.external_encoding).to eq(io.external_encoding)
    end
  end

  describe "closing" do
    it "cannot be closed through the wrapper, so smarter_csv leaves the consumer's IO open" do
      expect(source_io).not_to respond_to(:close)
    end
  end

  describe "#identifier" do
    it "is the file path when the IO has one" do
      file = File.open(csv_file("A\n1\n"))

      expect(described_class.new(io: file).identifier).to eq(file.path)
    end

    it "is the class name when the IO has no path" do
      expect(source_io.identifier).to eq("StringIO")
    end
  end
end
