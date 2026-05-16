# frozen_string_literal: true

RSpec.describe DiscourseWorkflows::NodeData do
  describe ".split" do
    it "stores credential references by declared slot" do
      split =
        described_class.split(
          node_type: "action:http_request",
          parameters: {
            "authentication" => "basic_auth",
          },
          credentials: {
            "auth" => {
              "id" => 12,
              "credential_type" => "basic_auth",
            },
          },
        )

      expect(split["parameters"]).to eq("authentication" => "basic_auth")
      expect(split["credentials"]).to eq(
        "auth" => {
          "id" => "12",
          "credential_type" => "basic_auth",
        },
      )
    end

    it "does not store magic credential_id parameters" do
      split =
        described_class.split(
          node_type: "action:http_request",
          parameters: {
            "authentication" => "basic_auth",
            "credential_id" => 12,
          },
        )

      expect(split["parameters"]).to eq("authentication" => "basic_auth")
      expect(split["credentials"]).to eq({})
    end

    it "removes stored credentials hidden by credential display options" do
      split =
        described_class.split(
          node_type: "action:http_request",
          parameters: {
            "authentication" => "none",
          },
          credentials: {
            "auth" => {
              "id" => 12,
              "credential_type" => "basic_auth",
            },
          },
        )

      expect(split["credentials"]).to eq({})
    end

    it "removes credentials from node types without credential declarations" do
      split =
        described_class.split(
          node_type: "action:log",
          parameters: {
            "message" => "hello",
          },
          credentials: {
            "auth" => {
              "id" => 12,
              "credential_type" => "basic_auth",
            },
          },
        )

      expect(split["credentials"]).to eq({})
    end
  end

  describe ".resolved_parameters" do
    it "does not merge credential references into ordinary parameters" do
      node = {
        "parameters" => {
          "authentication" => "basic_auth",
        },
        "credentials" => {
          "auth" => {
            "id" => "12",
            "credential_type" => "basic_auth",
          },
        },
      }

      expect(described_class.resolved_parameters(node)).to eq("authentication" => "basic_auth")
    end
  end
end
