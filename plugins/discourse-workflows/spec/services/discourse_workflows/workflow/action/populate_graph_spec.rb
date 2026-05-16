# frozen_string_literal: true

RSpec.describe DiscourseWorkflows::Workflow::Action::PopulateGraph do
  fab!(:workflow, :discourse_workflows_workflow)

  describe ".call" do
    context "when node count exceeds the maximum" do
      it "returns false and adds an error to the workflow" do
        nodes_data =
          (described_class::MAX_NODES + 1).times.map do |i|
            { client_id: "node-#{i}", type: "trigger:topic_created", name: "Node #{i}" }
          end

        result =
          described_class.call(workflow: workflow, nodes_data: nodes_data, connections_data: [])

        expect(result).to eq(false)
        expect(workflow.errors.full_messages).to include(
          /cannot have more than #{described_class::MAX_NODES}/,
        )
      end

      it "accepts exactly the maximum number of nodes" do
        nodes_data =
          described_class::MAX_NODES.times.map do |i|
            { client_id: "node-#{i}", type: "trigger:topic_created", name: "Node #{i}" }
          end

        result =
          described_class.call(workflow: workflow, nodes_data: nodes_data, connections_data: [])

        expect(result).to eq(true)
        expect(workflow.reload.nodes.size).to eq(described_class::MAX_NODES)
      end
    end

    context "when nodes have invalid versions" do
      it "returns false and adds errors to the workflow" do
        result =
          described_class.call(
            workflow: workflow,
            nodes_data: [
              {
                client_id: "node-1",
                type: "trigger:topic_created",
                type_version: "99.0",
                name: "Bad",
              },
            ],
            connections_data: [],
          )

        expect(result).to eq(false)
        expect(workflow.errors.full_messages).to include(
          "Unsupported version 99.0 for trigger:topic_created",
        )
      end
    end

    context "when a node type has multiple versions" do
      it "uses the latest version for new nodes without a submitted type_version" do
        v1 =
          Class.new(DiscourseWorkflows::NodeType) do
            description(name: "action:populate_versioned_test", version: "1.0")
          end
        v2 =
          Class.new(DiscourseWorkflows::NodeType) do
            description(name: "action:populate_versioned_test", version: "2.0")
          end

        DiscoursePluginRegistry.register_discourse_workflows_node(v1, Plugin::Instance.new)
        DiscoursePluginRegistry.register_discourse_workflows_node(v2, Plugin::Instance.new)
        DiscourseWorkflows::Registry.reset_indexes!

        result =
          described_class.call(
            workflow: workflow,
            nodes_data: [
              { client_id: "node-1", type: "action:populate_versioned_test", name: "Versioned" },
            ],
            connections_data: [],
          )

        expect(result).to eq(true)
        expect(workflow.reload.nodes.first["type_version"]).to eq("2.0")
      ensure
        DiscoursePluginRegistry._raw_discourse_workflows_nodes.reject! do |entry|
          [v1, v2].include?(entry[:value])
        end
        DiscourseWorkflows::Registry.reset_indexes!
      end
    end

    context "with nodes and connections" do
      let(:nodes_data) do
        [
          { client_id: "node-1", type: "trigger:topic_created", name: "Topic Created" },
          {
            client_id: "node-2",
            type: "action:topic_tags",
            name: "Topic Tags",
            parameters: {
              "tag_names" => "processed",
            },
          },
          { client_id: "node-3", type: "action:log", name: "Log" },
        ]
      end

      let(:connections_data) do
        [
          { source_client_id: "node-1", target_client_id: "node-2", source_output_index: 0 },
          { source_client_id: "node-2", target_client_id: "node-3" },
        ]
      end

      it "creates nodes with correct attributes and position indices" do
        described_class.call(
          workflow: workflow,
          nodes_data: nodes_data,
          connections_data: connections_data,
        )

        workflow.reload
        nodes = workflow.nodes.sort_by { |n| n["position_index"] }
        expect(nodes.size).to eq(3)

        expect(nodes[0]).to include(
          "type" => "trigger:topic_created",
          "name" => "Topic Created",
          "position_index" => 0,
          "parameters" => {
          },
          "credentials" => {
          },
          "settings" => {
          },
        )
        expect(nodes[1]).to include(
          "type" => "action:topic_tags",
          "name" => "Topic Tags",
          "position_index" => 1,
          "parameters" => {
            "tag_names" => "processed",
          },
          "credentials" => {
          },
          "settings" => {
          },
        )
        expect(nodes[2]).to include(
          "type" => "action:log",
          "name" => "Log",
          "position_index" => 2,
          "parameters" => {
          },
          "credentials" => {
          },
          "settings" => {
          },
        )
      end

      it "creates connections with correct attributes" do
        described_class.call(
          workflow: workflow,
          nodes_data: nodes_data,
          connections_data: connections_data,
        )

        workflow.reload
        nodes = workflow.nodes.sort_by { |n| n["position_index"] }
        connections = workflow.connections
        expect(connections.size).to eq(2)

        expect(connections[0]).to include(
          "source_node_id" => nodes[0]["id"],
          "target_node_id" => nodes[1]["id"],
          "connection_type" => "main",
          "source_output_index" => 0,
          "target_input_index" => 0,
        )
        expect(connections[1]).to include(
          "source_node_id" => nodes[1]["id"],
          "target_node_id" => nodes[2]["id"],
          "connection_type" => "main",
          "source_output_index" => 0,
          "target_input_index" => 0,
        )
      end
    end

    context "with split node data" do
      it "stores parameters, credentials, and settings separately" do
        described_class.call(
          workflow: workflow,
          nodes_data: [
            {
              client_id: "http-1",
              type: "action:http_request",
              name: "HTTP request",
              parameters: {
                "url" => "https://example.com",
                "method" => "GET",
                "authentication" => "basic_auth",
                "credential_id" => 12,
                "description" => "Fetches data",
              },
            },
          ],
          connections_data: [],
        )

        node = workflow.reload.nodes.first
        expect(node["parameters"]).to eq(
          "url" => "https://example.com",
          "method" => "GET",
          "authentication" => "basic_auth",
        )
        expect(node["credentials"]).to eq(
          "auth" => {
            "id" => "12",
            "field_name" => "credential_id",
            "credential_type" => "basic_auth",
          },
        )
        expect(node["settings"]).to eq("description" => "Fetches data")
      end

      it "removes stale credentials when authentication no longer uses them" do
        described_class.call(
          workflow: workflow,
          nodes_data: [
            {
              client_id: "http-1",
              type: "action:http_request",
              name: "HTTP request",
              parameters: {
                "url" => "https://example.com",
                "method" => "GET",
                "authentication" => "none",
              },
              credentials: {
                "auth" => {
                  "id" => "12",
                  "field_name" => "credential_id",
                  "credential_type" => "basic_auth",
                },
              },
            },
          ],
          connections_data: [],
        )

        expect(workflow.reload.nodes.first["credentials"]).to eq({})
      end
    end

    context "when workflow has existing nodes and connections" do
      before do
        extra =
          build_workflow_graph do |g|
            g.node "existing-1", "action:topic_tags", name: "Existing Node 1"
            g.node "existing-2", "action:topic_tags", name: "Existing Node 2"
            g.chain "existing-1", "existing-2"
          end
        workflow.update!(nodes: extra[:nodes], connections: extra[:connections])
      end

      it "removes stale nodes and creates new ones" do
        described_class.call(
          workflow: workflow,
          nodes_data: [{ client_id: "new-1", type: "trigger:topic_created", name: "New Node" }],
          connections_data: [],
        )

        workflow.reload
        expect(workflow.nodes.map { |n| n["name"] }).to eq(["New Node"])
        expect(workflow.connections).to be_empty
      end

      it "preserves the existing node's id and type_version" do
        described_class.call(
          workflow: workflow,
          nodes_data: [
            {
              client_id: "existing-1",
              type: "action:topic_tags",
              name: "Updated Name",
              parameters: {
                "tag_names" => "new",
              },
            },
          ],
          connections_data: [],
        )

        node = workflow.reload.nodes.first
        expect(node["id"]).to eq("existing-1")
        expect(node["type_version"]).to eq("1.0")
        expect(node["name"]).to eq("Updated Name")
      end

      it "preserves static_data for removed nodes" do
        workflow.update!(
          static_data: {
            "existing-1" => {
              "key" => "value",
            },
            "existing-2" => {
              "seconds_tokens" => {
                "0" => "token",
              },
            },
          },
        )

        described_class.call(
          workflow: workflow,
          nodes_data: [
            {
              client_id: "existing-1",
              type: "action:topic_tags",
              name: "Kept Node",
              parameters: {
              },
            },
          ],
          connections_data: [],
        )

        workflow.reload
        expect(workflow.static_data).to have_key("existing-1")
        expect(workflow.static_data).to have_key("existing-2")
      end
    end

    context "with connections referencing non-existent client IDs" do
      let(:nodes_data) do
        [{ client_id: "node-1", type: "trigger:topic_created", name: "Topic Created" }]
      end

      let(:connections_data) { [{ source_client_id: "node-1", target_client_id: "missing-node" }] }

      it "skips connections with invalid references" do
        described_class.call(
          workflow: workflow,
          nodes_data: nodes_data,
          connections_data: connections_data,
        )

        workflow.reload
        expect(workflow.nodes.size).to eq(1)
        expect(workflow.connections).to be_empty
      end
    end

    context "when creating a form trigger without a uuid" do
      it "assigns a generated uuid" do
        described_class.call(
          workflow: workflow,
          nodes_data: [{ client_id: "form-1", type: "trigger:form", name: "Form" }],
          connections_data: [],
        )

        workflow.reload
        expect(workflow.nodes.first["webhook_id"]).to be_present
      end
    end

    context "when a form trigger already has a webhook_id" do
      it "preserves the existing webhook_id" do
        described_class.call(
          workflow: workflow,
          nodes_data: [
            {
              client_id: "form-1",
              type: "trigger:form",
              name: "Form",
              webhook_id: "existing-uuid",
            },
          ],
          connections_data: [],
        )

        expect(workflow.reload.nodes.first["webhook_id"]).to eq("existing-uuid")
      end
    end

    context "when an existing form trigger is updated" do
      before do
        extra =
          build_workflow_graph { |g| g.node "form-1", "trigger:form", webhook_id: "original-uuid" }
        workflow.update!(nodes: extra[:nodes])
      end

      it "preserves the original webhook_id" do
        described_class.call(
          workflow: workflow,
          nodes_data: [
            {
              client_id: "form-1",
              type: "trigger:form",
              name: "Updated Form",
              parameters: {
                "some_field" => "value",
              },
            },
          ],
          connections_data: [],
        )

        node = workflow.reload.nodes.first
        expect(node["webhook_id"]).to eq("original-uuid")
        expect(node.dig("parameters", "some_field")).to eq("value")
      end
    end
  end
end
