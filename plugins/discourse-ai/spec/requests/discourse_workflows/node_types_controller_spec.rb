# frozen_string_literal: true

RSpec.describe DiscourseWorkflows::DynamicNodeParametersController do
  fab!(:admin)
  fab!(:agent_1) { Fabricate(:ai_agent, name: "Alpha agent", enabled: true) }
  fab!(:agent_2) { Fabricate(:ai_agent, name: "Beta agent", enabled: false) }
  fab!(:agent_3) { Fabricate(:ai_agent, name: "Gamma agent", enabled: true) }

  before do
    enable_current_plugin
    sign_in(admin)
    SiteSetting.discourse_ai_enabled = true
    DiscourseWorkflows::Registry.reset_indexes!
  end

  describe "POST /admin/plugins/discourse-workflows/dynamic-node-parameters/options" do
    it "returns enabled AI agents for the AI agent node" do
      post "/admin/plugins/discourse-workflows/dynamic-node-parameters/options.json",
           params: {
             nodeTypeAndVersion: {
               name: "action:ai_agent",
               version: "1.0",
             },
             path: "agent_id",
             methodName: "agents",
           },
           as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("id" => agent_1.id, "name" => agent_1.name)
      expect(response.parsed_body).not_to include("id" => agent_2.id, "name" => agent_2.name)
    end

    it "filters AI agents by the filter term" do
      post "/admin/plugins/discourse-workflows/dynamic-node-parameters/options.json",
           params: {
             nodeTypeAndVersion: {
               name: "action:ai_agent",
               version: "1.0",
             },
             path: "agent_id",
             methodName: "agents",
             filter: "alpha",
           },
           as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("id" => agent_1.id, "name" => agent_1.name)
      expect(response.parsed_body).not_to include("id" => agent_3.id, "name" => agent_3.name)
    end
  end
end
