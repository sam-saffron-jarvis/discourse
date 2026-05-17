# frozen_string_literal: true

RSpec.describe DiscourseWorkflows::NodeTypesController do
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

  describe "GET /admin/plugins/discourse-workflows/node-types/:identifier/options/:source_key" do
    it "returns enabled AI agents for the AI agent node" do
      get "/admin/plugins/discourse-workflows/node-types/action%3Aai_agent/options/agents.json"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["options"]).to include("id" => agent_1.id, "name" => agent_1.name)
      expect(response.parsed_body["options"]).not_to include(
        "id" => agent_2.id,
        "name" => agent_2.name,
      )
    end

    it "filters AI agents by search term" do
      get "/admin/plugins/discourse-workflows/node-types/action%3Aai_agent/options/agents.json",
          params: {
            search: "alpha",
          }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["options"]).to include("id" => agent_1.id, "name" => agent_1.name)
      expect(response.parsed_body["options"]).not_to include(
        "id" => agent_3.id,
        "name" => agent_3.name,
      )
    end
  end
end
