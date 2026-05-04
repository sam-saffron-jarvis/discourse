# frozen_string_literal: true

RSpec.describe "Discourse Workflows - Form Trigger" do
  FORM_UUID = "a1b2c3d4-e5f6-7890-abcd-ef0123456789"

  fab!(:workflow) do
    Fabricate(
      :discourse_workflows_workflow,
      enabled: true,
      nodes: [
        {
          "id" => "trigger-1",
          "type" => "trigger:form",
          "type_version" => "1.0",
          "name" => "Form Trigger",
          "position_index" => 0,
          "configuration" => {
            "uuid" => FORM_UUID,
            "form_title" => "Contact Us",
            "form_fields" => [
              { "field_label" => "Your name", "field_type" => "text", "required" => true },
            ],
            "response_mode" => "on_received",
            "authentication" => "none",
          },
        },
      ],
      connections: [],
    )
  end

  before { DiscourseWorkflows::WorkflowDependencyIndexer.call(workflow) }

  it "renders the public form" do
    page.visit("/workflows/form/#{FORM_UUID}")

    expect(page).to have_css(".workflows-form")
    expect(page).to have_css(".workflows-form__title", text: "Contact Us")
    expect(page).to have_css("input[name='your_name']")
  end

  it "submits the form and shows completion" do
    page.visit("/workflows/form/#{FORM_UUID}")

    find("input[name='your_name']").fill_in(with: "Alice")
    find(".workflows-form .btn-primary[type='submit']").click

    expect(page).to have_css(".workflows-form__complete")
  end
end
