import { render } from "@ember/test-helpers";
import { module, test } from "qunit";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";
import WorkflowsForm from "discourse/plugins/discourse-workflows/discourse/components/workflows-form";

module("Integration | Component | workflows-form", function (hooks) {
  setupRenderingTest(hooks);

  test("renders backend FormKit schema with FormKit controls", async function (assert) {
    this.set("model", {
      uuid: "a1b2c3d4-e5f6-7890-abcd-ef0123456789",
      form_title: "Intake",
      form_kit_schema: {
        data: {
          name: "",
          age: "",
          bio: "",
          plan: "basic",
        },
        fields: [
          {
            name: "name",
            title: "Name",
            type: "input",
            validation: "required",
            placeholder: "Your name",
          },
          {
            name: "age",
            title: "Age",
            type: "input-number",
          },
          {
            name: "bio",
            title: "Bio",
            type: "textarea",
            placeholder: "Tell us more",
          },
          {
            name: "plan",
            title: "Plan",
            type: "select",
            options: [
              { value: "basic", label: "Basic" },
              { value: "pro", label: "Pro" },
            ],
          },
        ],
      },
    });

    await render(<template><WorkflowsForm @model={{this.model}} /></template>);

    assert.dom(".workflows-form__title").hasText("Intake");
    assert.dom('[data-name="name"]').hasClass("form-kit__field-input");
    assert.dom('input[name="name"]').hasAttribute("placeholder", "Your name");
    assert.dom('[data-name="age"]').hasClass("form-kit__field-input-number");
    assert.dom('input[name="age"]').hasAttribute("type", "number");
    assert
      .dom('textarea[name="bio"]')
      .hasAttribute("placeholder", "Tell us more");
    assert.dom('select[name="plan"]').exists();
    assert.dom('option[value="basic"]').hasText("Basic");
    assert.dom('option[value="pro"]').hasText("Pro");
  });
});
