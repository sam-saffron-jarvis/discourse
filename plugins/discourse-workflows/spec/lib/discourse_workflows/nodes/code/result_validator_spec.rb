# frozen_string_literal: true

RSpec.describe DiscourseWorkflows::Nodes::Code::ResultValidator do
  def validator
    error_handler =
      Class
        .new(DiscourseWorkflows::NodeType) do
          def call(message, description:, item_index: nil, line_number: nil)
            raise_node_error!(message, description:, item_index:, line_number:)
          end
        end
        .new

    described_class.new(
      normalize_items: ->(value) { DiscourseWorkflows::Item.normalize_items(value) },
      raise_error:
        lambda do |message, description:, item_index: nil, line_number: nil|
          error_handler.call(message, description:, item_index:, line_number:)
        end,
    )
  end

  describe "#validate_each_item" do
    it "wraps a plain object and adds pairedItem metadata" do
      result =
        validator.validate_each_item(
          { "type" => "object", "value" => { "name" => "Ada" } },
          item_index: 2,
        )

      expect(result).to eq("json" => { "name" => "Ada" }, "pairedItem" => { "item" => 2 })
    end

    it "normalizes explicit pairedItem shorthand" do
      result =
        validator.validate_each_item(
          { "type" => "object", "value" => { "json" => { "name" => "Ada" }, "pairedItem" => 1 } },
          item_index: 2,
        )

      expect(result).to eq("json" => { "name" => "Ada" }, "pairedItem" => { "item" => 1 })
    end

    it "raises when the code returns a primitive" do
      expect {
        validator.validate_each_item({ "type" => "string", "value" => "nope" }, item_index: 0)
      }.to raise_error(
        DiscourseWorkflows::NodeError,
        "Code doesn't return an object [item 0]: Please return an object representing the output item. ('nope' was returned instead.)",
      )
    end

    it "raises when the code returns an array" do
      expect {
        validator.validate_each_item(
          { "type" => "object", "value" => [{ "json" => { "n" => 1 } }] },
          item_index: 0,
        )
      }.to raise_error(DiscourseWorkflows::NodeError, /Code doesn't return a single object/)
    end

    it "raises when json is not an object" do
      expect {
        validator.validate_each_item(
          { "type" => "object", "value" => { "json" => "bad" } },
          item_index: 0,
        )
      }.to raise_error(DiscourseWorkflows::NodeError, /A 'json' property isn't an object/)
    end

    it "raises when an item-shaped return has unknown top-level keys" do
      expect {
        validator.validate_each_item(
          { "type" => "object", "value" => { "json" => {}, "extra" => true } },
          item_index: 0,
        )
      }.to raise_error(DiscourseWorkflows::NodeError, /Invalid output format/)
    end
  end

  describe "#validate_all_items" do
    it "wraps an array of plain objects" do
      result =
        validator.validate_all_items(
          { "type" => "object", "value" => [{ "name" => "Ada" }, { "name" => "Grace" }] },
        )

      expect(result).to eq([{ "json" => { "name" => "Ada" } }, { "json" => { "name" => "Grace" } }])
    end

    it "wraps a single plain object" do
      result = validator.validate_all_items({ "type" => "object", "value" => { "count" => 2 } })

      expect(result).to eq([{ "json" => { "count" => 2 } }])
    end

    it "preserves item-shaped returns and normalizes pairedItem" do
      result =
        validator.validate_all_items(
          {
            "type" => "object",
            "value" => [{ "json" => { "name" => "Ada" }, "pairedItem" => { "item" => 0 } }],
          },
        )

      expect(result).to eq([{ "json" => { "name" => "Ada" }, "pairedItem" => { "item" => 0 } }])
    end

    it "normalizes binary-only array items" do
      result =
        validator.validate_all_items(
          {
            "type" => "object",
            "value" => [{ "binary" => { "data" => { "mimeType" => "text/plain" } } }],
          },
        )

      expect(result).to eq(
        [{ "json" => {}, "binary" => { "data" => { "mimeType" => "text/plain" } } }],
      )
    end

    it "allows an empty array" do
      expect(validator.validate_all_items({ "type" => "object", "value" => [] })).to eq([])
    end

    it "raises when the code returns a primitive" do
      expect { validator.validate_all_items({ "type" => "number", "value" => 1 }) }.to raise_error(
        DiscourseWorkflows::NodeError,
        /Code doesn't return items properly/,
      )
    end

    it "raises when an array contains a primitive" do
      expect {
        validator.validate_all_items({ "type" => "object", "value" => [1] })
      }.to raise_error(DiscourseWorkflows::NodeError, /Code doesn't return items properly/)
    end

    it "raises when item-shaped and plain return formats are mixed" do
      expect {
        validator.validate_all_items(
          { "type" => "object", "value" => [{ "json" => { "id" => 1 } }, { "id" => 2 }] },
        )
      }.to raise_error(DiscourseWorkflows::NodeError, /Unknown top-level item key: id/)
    end

    it "raises a node error when reserved item formats are mixed" do
      expect {
        validator.validate_all_items(
          { "type" => "object", "value" => [{ "json" => { "id" => 1 } }, { "binary" => {} }] },
        )
      }.to raise_error(
        DiscourseWorkflows::NodeError,
        "Inconsistent item format: Every returned item must use the same format.",
      )
    end
  end
end
