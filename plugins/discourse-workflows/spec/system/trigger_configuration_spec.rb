# frozen_string_literal: true

RSpec.describe "Discourse Workflows - Trigger Configuration" do
  fab!(:admin)

  let(:editor_page) { PageObjects::Pages::WorkflowEditor.new }

  before { sign_in(admin) }

  context "with a webhook trigger" do
    it "shows the webhook URL preview in the configurator" do
      editor_page.visit_new
      editor_page.click_empty_state_add_node
      editor_page.select_node_type("trigger:webhook")
      editor_page.double_click_node(0)

      expect(editor_page).to have_node_configurator
      expect(page).to have_css(".workflows-url-preview")
    end
  end

  context "with a schedule trigger" do
    it "shows the schedule rules configurator" do
      editor_page.visit_new
      editor_page.click_empty_state_add_node
      editor_page.select_node_type("trigger:schedule")
      editor_page.double_click_node(0)

      expect(editor_page).to have_node_configurator
      expect(page).to have_css(".workflows-configurator-form")
    end
  end
end
