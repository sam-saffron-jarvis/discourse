# frozen_string_literal: true

RSpec.describe DiscourseWorkflows::NodeTypesController do
  fab!(:admin)

  before { sign_in(admin) }

  context "when not logged in as admin" do
    fab!(:user)

    before { sign_in(user) }

    it "returns 404" do
      get "/admin/plugins/discourse-workflows/node-types.json"
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /admin/plugins/discourse-workflows/node-types" do
    it "returns all registered node types" do
      get "/admin/plugins/discourse-workflows/node-types.json"

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      identifiers = json["node_types"].map { |nt| nt["identifier"] }

      expect(identifiers).to include("trigger:topic_closed")
      expect(identifiers).to include("action:topic_tags")
      expect(identifiers).to include("action:create_post")
      expect(identifiers).to include("action:create_topic")
      expect(identifiers).to include("condition:if")
    end

    it "does not include metadata key in node type response" do
      get "/admin/plugins/discourse-workflows/node-types.json"

      badge_node =
        response.parsed_body["node_types"].find { |nt| nt["identifier"] == "action:badge" }
      expect(badge_node).not_to have_key("metadata")
    end

    it "returns descriptor fields used by the admin client" do
      get "/admin/plugins/discourse-workflows/node-types.json"

      condition =
        response.parsed_body["node_types"].find do |node_type|
          node_type["identifier"] == "condition:if"
        end

      expect(condition["ui"]["palette_group"]).to include("id" => "flow")
      expect(condition["capabilities"]).to include(
        "branching" => true,
        "manually_triggerable" => false,
        "result_mode" => "ports",
      )
      expect(condition["ports"]).to include(
        a_hash_including(
          "key" => "true",
          "label_key" => "discourse_workflows.branch.true",
          "primary" => true,
        ),
      )
      expect(condition["inputs"]).to include(a_hash_including("key" => "main", "required" => true))
    end
  end

  describe "GET /admin/plugins/discourse-workflows/node-types/:identifier/options/:source_key" do
    fab!(:badge) { Fabricate(:badge, name: "Helpful") }
    fab!(:group_1) { Fabricate(:group, name: "alpha") }

    it "returns options for a known source key" do
      get "/admin/plugins/discourse-workflows/node-types/action%3Abadge/options/badges.json"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["options"]).to include("id" => badge.id, "name" => badge.name)
    end

    it "returns groups for the group node" do
      get "/admin/plugins/discourse-workflows/node-types/action%3Agroup/options/groups.json"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["options"]).to include("id" => group_1.id, "name" => group_1.name)
    end

    it "returns 404 for an unknown node type" do
      get "/admin/plugins/discourse-workflows/node-types/action%3Aunknown/options/badges.json"
      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 for an unknown source key" do
      get "/admin/plugins/discourse-workflows/node-types/action%3Abadge/options/nonexistent.json"
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /admin/plugins/discourse-workflows/node-types/:identifier/options/:source_key" do
    it "passes structured load-options context to context-aware nodes" do
      credential =
        Fabricate(
          :discourse_workflows_credential,
          credential_type: "basic_auth",
          data:
            DiscourseWorkflows::CredentialEncryptor.encrypt(
              { "user" => "static-user", "password" => "static-password" },
            ),
        )
      node_class =
        Class.new(DiscourseWorkflows::NodeType) do
          description(
            name: "action:load_options_context_test",
            credentials: [
              {
                name: "auth",
                credential_types: %w[basic_auth],
                displayOptions: {
                  show: {
                    authentication: %w[basic_auth],
                  },
                },
              },
            ],
          )

          def self.load_options_context(context)
            [
              {
                id: context.current_node_parameter("operation"),
                name: context.search,
                property_name: context.property_name,
                workflow_id: context.workflow_id,
                credential_slots: context.credentials.keys,
                credential_id: context.credential_reference("auth")["id"],
                credential_user: context.get_credentials("auth")["user"],
                node_id: context.node_id,
                input_subject: context.input_context.dig("item", "json", "subject"),
                execution_value: context.execution_context.dig("preview", "value"),
                user_id: context.user.id,
              },
            ]
          end
        end

      DiscoursePluginRegistry.register_discourse_workflows_node(node_class, Plugin::Instance.new)
      DiscourseWorkflows::Registry.reset_indexes!

      post "/admin/plugins/discourse-workflows/node-types/action%3Aload_options_context_test/options/things.json",
           params: {
             parameters: {
               authentication: "basic_auth",
               operation: "list",
             },
             credentials: {
               auth: {
                 id: credential.id,
                 credential_type: "basic_auth",
               },
               ignored: {
                 id: credential.id,
                 credential_type: "basic_auth",
               },
             },
             property_name: "thing_id",
             node: {
               id: "node-1",
               name: "Context test",
             },
             workflow_id: "42",
             input_context: {
               item: {
                 json: {
                   subject: "From input item",
                 },
               },
             },
             execution_context: {
               preview: {
                 value: "from-preview",
               },
             },
             search: "alp",
           },
           as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["options"]).to contain_exactly(
        "id" => "list",
        "name" => "alp",
        "property_name" => "thing_id",
        "workflow_id" => "42",
        "credential_slots" => ["auth"],
        "credential_id" => credential.id.to_s,
        "credential_user" => "static-user",
        "node_id" => "node-1",
        "input_subject" => "From input item",
        "execution_value" => "from-preview",
        "user_id" => admin.id,
      )
    ensure
      DiscoursePluginRegistry._raw_discourse_workflows_nodes.reject! do |entry|
        entry[:value] == node_class
      end
      DiscourseWorkflows::Registry.reset_indexes!
    end

    it "uses the requested node version when loading options" do
      v1 =
        Class.new(DiscourseWorkflows::NodeType) do
          description(name: "action:load_options_version_test", version: "1.0")

          def self.load_options_context(_context)
            [{ id: "v1", name: "Version 1" }]
          end
        end
      v2 =
        Class.new(DiscourseWorkflows::NodeType) do
          description(name: "action:load_options_version_test", version: "2.0")

          def self.load_options_context(_context)
            [{ id: "v2", name: "Version 2" }]
          end
        end

      DiscoursePluginRegistry.register_discourse_workflows_node(v1, Plugin::Instance.new)
      DiscoursePluginRegistry.register_discourse_workflows_node(v2, Plugin::Instance.new)
      DiscourseWorkflows::Registry.reset_indexes!

      post "/admin/plugins/discourse-workflows/node-types/action%3Aload_options_version_test/options/things.json",
           params: {
             version: "1.0",
           },
           as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["options"]).to contain_exactly(
        "id" => "v1",
        "name" => "Version 1",
      )

      post "/admin/plugins/discourse-workflows/node-types/action%3Aload_options_version_test/options/things.json",
           params: {
             node: {
               type_version: "2.0",
             },
           },
           as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["options"]).to contain_exactly(
        "id" => "v2",
        "name" => "Version 2",
      )
    ensure
      DiscoursePluginRegistry._raw_discourse_workflows_nodes.reject! do |entry|
        [v1, v2].include?(entry[:value])
      end
      DiscourseWorkflows::Registry.reset_indexes!
    end

    it "keeps legacy load_options(source_key) support" do
      node_class =
        Class.new(DiscourseWorkflows::NodeType) do
          description(name: "action:legacy_load_options_test")

          def self.load_options(source_key)
            [{ id: source_key, name: source_key.upcase }]
          end
        end

      DiscoursePluginRegistry.register_discourse_workflows_node(node_class, Plugin::Instance.new)
      DiscourseWorkflows::Registry.reset_indexes!

      post "/admin/plugins/discourse-workflows/node-types/action%3Alegacy_load_options_test/options/legacy.json",
           as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["options"]).to contain_exactly(
        "id" => "legacy",
        "name" => "LEGACY",
      )
    ensure
      DiscoursePluginRegistry._raw_discourse_workflows_nodes.reject! do |entry|
        entry[:value] == node_class
      end
      DiscourseWorkflows::Registry.reset_indexes!
    end
  end
end
