# frozen_string_literal: true

RSpec.describe DiscourseWorkflows::Forms::FormKitSchema do
  describe ".build" do
    it "maps workflow form fields to FormKit field config and initial data" do
      schema =
        described_class.build(
          [
            {
              "field_label" => "Name",
              "field_type" => "text",
              "required" => true,
              "default_value" => "Ada",
              "placeholder" => "Your name",
            },
            { "field_label" => "Age", "field_type" => "number" },
            { "field_label" => "Agree", "field_type" => "checkbox", "default_value" => "true" },
            {
              "field_label" => "Plan",
              "field_name" => "plan_id",
              "field_type" => "dropdown",
              "options" => {
                "values" => [{ "value" => "basic" }, { "value" => "pro" }],
              },
            },
          ],
        )

      expect(schema[:data]).to eq("name" => "Ada", "age" => "", "agree" => true, "plan_id" => "")
      expect(schema[:fields]).to contain_exactly(
        {
          name: "name",
          title: "Name",
          type: "input",
          validation: "required",
          placeholder: "Your name",
          autofocus: false,
        },
        { name: "age", title: "Age", type: "input-number", autofocus: false },
        { name: "agree", title: "Agree", type: "checkbox", autofocus: false },
        {
          name: "plan_id",
          title: "Plan",
          type: "select",
          options: [{ value: "basic", label: "basic" }, { value: "pro", label: "pro" }],
          autofocus: false,
        },
      )
    end
  end
end
