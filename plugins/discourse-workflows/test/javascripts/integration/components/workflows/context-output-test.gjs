import { render } from "@ember/test-helpers";
import { module, test } from "qunit";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";
import OutputContext from "discourse/plugins/discourse-workflows/admin/components/workflows/context/output";

module("Integration | Component | workflows/context/output", function (hooks) {
  setupRenderingTest(hooks);

  test("uses the saved node type version for runtime output discovery", async function (assert) {
    const node = {
      clientId: "n1",
      type: "action:http_request",
      type_version: "1.0",
      configuration: {},
    };
    const nodes = [node];
    const nodeTypes = [
      {
        identifier: "action:http_request",
        latest: {
          version: "2.0",
          properties: {},
        },
        versions: {
          "1.0": {
            properties: {
              output_fields: {
                ui: {
                  hidden: true,
                },
              },
            },
          },
          "2.0": {
            properties: {},
          },
        },
      },
    ];

    await render(
      <template>
        <OutputContext
          @node={{node}}
          @nodes={{nodes}}
          @connections={{(Array)}}
          @nodeTypes={{nodeTypes}}
        />
      </template>
    );

    assert
      .dom(".workflows-context-panel__empty")
      .hasText("Run the workflow to discover output fields");
  });
});
