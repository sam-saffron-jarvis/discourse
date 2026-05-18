# frozen_string_literal: true

RSpec.describe DiscourseWorkflows::NodeType do
  around do |example|
    nodes_before = described_class.registered_nodes.dup
    example.run
    described_class.registered_nodes.replace(nodes_before)
  end

  describe ".inputs" do
    it "defaults to [:main]" do
      expect(described_class.inputs).to eq([:main])
    end
  end

  describe ".outputs" do
    it "defaults to [:main]" do
      expect(described_class.outputs).to eq([:main])
    end
  end

  describe ".webhooks" do
    it "defaults to an empty array" do
      expect(described_class.webhooks).to eq([])
    end

    it "normalizes webhook descriptors to symbol keys" do
      klass =
        Class.new(described_class) do
          description(
            webhooks: [
              {
                "path" => "status",
                "http_method" => "GET",
                "restart_webhook" => true,
                "node_type" => "form",
              },
            ],
          )
        end

      expect(klass.webhooks).to contain_exactly(
        path: "status",
        http_method: "GET",
        restart_webhook: true,
        node_type: "form",
      )
    end
  end

  describe ".waiting_webhook_for" do
    it "finds a matching restart webhook descriptor" do
      klass =
        Class.new(described_class) do
          description(
            webhooks: [{ path: "", http_method: "POST", restart_webhook: true, node_type: "form" }],
          )
        end

      expect(klass.waiting_webhook_for(http_method: "post", path: "", node_type: "form")).to eq(
        path: "",
        http_method: "POST",
        restart_webhook: true,
        node_type: "form",
      )
    end

    it "ignores non-restart webhook descriptors" do
      klass =
        Class.new(described_class) do
          description(webhooks: [{ path: "", http_method: "POST", node_type: "form" }])
        end

      expect(klass.waiting_webhook_for(http_method: "POST", path: "", node_type: "form")).to be_nil
    end
  end

  describe ".branching?" do
    it "returns false when single output" do
      expect(described_class.branching?).to eq(false)
    end

    it "returns true when multiple outputs" do
      klass =
        Class.new(described_class) do
          description(outputs: [{ key: "true", label_key: "t" }, { key: "false", label_key: "f" }])
        end
      expect(klass.branching?).to eq(true)
    end
  end

  describe ".available?" do
    it "defaults to true" do
      expect(described_class.available?).to eq(true)
    end

    it "can be overridden by subclass" do
      klass =
        Class.new(described_class) { description(name: "action:unavailable", available: false) }
      expect(klass.available?).to eq(false)
    end
  end

  describe ".unavailable_reason_key" do
    it "defaults to nil" do
      expect(described_class.unavailable_reason_key).to be_nil
    end
  end

  describe ".output_exemplar" do
    it "returns an empty hash when output_schema is empty" do
      expect(described_class.output_exemplar).to eq({})
    end

    it "builds an exemplar from the output schema" do
      klass =
        Class.new(described_class) do
          description(output_schema: { title: :string, count: :integer })
        end

      expect(klass.output_exemplar).to eq({ "title" => "", "count" => 0 })
    end
  end

  describe ".exemplar_from_schema" do
    it "maps primitive types to their default values" do
      schema = {
        title: :string,
        count: :integer,
        score: :number,
        active: :boolean,
        tags: :array,
        meta: :object,
      }

      expect(described_class.exemplar_from_schema(schema)).to eq(
        "title" => "",
        "count" => 0,
        "score" => 0,
        "active" => false,
        "tags" => [],
        "meta" => {
        },
      )
    end

    it "stringifies symbol keys" do
      expect(described_class.exemplar_from_schema(title: :string)).to eq("title" => "")
    end

    it "recurses into nested hashes" do
      schema = { topic: { id: :integer, title: :string, tags: :array } }

      expect(described_class.exemplar_from_schema(schema)).to eq(
        "topic" => {
          "id" => 0,
          "title" => "",
          "tags" => [],
        },
      )
    end

    it "defaults unknown types to an empty string" do
      expect(described_class.exemplar_from_schema(unknown: :not_a_type)).to eq("unknown" => "")
    end

    it "treats hashes with :type as field definitions, not nested schemas" do
      schema = {
        body: {
          type: :object,
          visible_if: {
            resume: "webhook",
          },
        },
        method: {
          type: :string,
          visible_if: {
            resume: "webhook",
          },
        },
      }

      expect(described_class.exemplar_from_schema(schema)).to eq("body" => {}, "method" => "")
    end

    it "expands :object field definitions with :fields" do
      schema = {
        user: {
          type: :object,
          fields: {
            id: :integer,
            email: :string,
          },
          visible_if: {
            operation: "assign",
          },
        },
      }

      expect(described_class.exemplar_from_schema(schema)).to eq(
        "user" => {
          "id" => 0,
          "email" => "",
        },
      )
    end
  end

  describe "Wait.output_exemplar" do
    it "does not leak schema metadata into the exemplar" do
      exemplar = DiscourseWorkflows::Nodes::Wait::V1.output_exemplar
      expect(exemplar.keys).to match_array(%w[body headers query method webhook_url])
      expect(exemplar).not_to have_key("visible_if")
      expect(exemplar["method"]).to eq("")
      expect(exemplar["body"]).to eq({})
    end
  end

  describe "#with_paired_item" do
    it "adds normalized paired item metadata to an item" do
      node = described_class.new
      item = { "json" => { "name" => "Ada" } }

      expect(node.send(:with_paired_item, item, { item: 1 })).to eq(
        "json" => {
          "name" => "Ada",
        },
        "pairedItem" => {
          "item" => 1,
        },
      )
    end
  end
end
