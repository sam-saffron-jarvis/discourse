# frozen_string_literal: true

RSpec.describe DiscourseWorkflows::Item do
  describe ".wrap" do
    it "wraps a hash with stringified keys" do
      expect(described_class.wrap(name: "Alice")).to eq("json" => { "name" => "Alice" })
    end

    it "deep-stringifies nested keys" do
      expect(described_class.wrap(outer: { inner: "val" })).to eq(
        "json" => {
          "outer" => {
            "inner" => "val",
          },
        },
      )
    end

    it "freezes the inner json hash" do
      expect(described_class.wrap("key" => "value")["json"]).to be_frozen
    end

    it "maps over an array of hashes" do
      expect(described_class.wrap([{ "name" => "A" }, { "name" => "B" }])).to eq(
        [{ "json" => { "name" => "A" } }, { "json" => { "name" => "B" } }],
      )
    end

    it "adds n8n-compatible pairedItem metadata" do
      expect(described_class.wrap({ "name" => "A" }, paired_item: { item: 1 })).to eq(
        "json" => {
          "name" => "A",
        },
        "pairedItem" => {
          "item" => 1,
        },
      )
    end

    it "raises when given something other than a Hash or Array" do
      expect { described_class.wrap(nil) }.to raise_error(ArgumentError)
      expect { described_class.wrap("string") }.to raise_error(ArgumentError)
    end
  end
end
