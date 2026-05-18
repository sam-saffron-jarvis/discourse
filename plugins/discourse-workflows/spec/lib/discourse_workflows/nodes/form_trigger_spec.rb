# frozen_string_literal: true

RSpec.describe DiscourseWorkflows::Nodes::FormTrigger::V1 do
  describe "#output" do
    it "returns compatible form data and metadata" do
      trigger =
        described_class.new(
          form_data: {
            name: "Test",
          },
          submitted_at: "2026-01-01T00:00:00.000Z",
          query_parameters: {
            source: "email",
          },
        )

      expect(trigger.output).to eq(
        "name" => "Test",
        "submittedAt" => "2026-01-01T00:00:00.000Z",
        "formMode" => "production",
        "formQueryParameters" => {
          "source" => "email",
        },
      )
    end
  end
end
