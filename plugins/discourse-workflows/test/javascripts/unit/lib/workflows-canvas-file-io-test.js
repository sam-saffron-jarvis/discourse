import { module, test } from "qunit";
import {
  buildWorkflowExportPayload,
  parseWorkflowImport,
} from "discourse/plugins/discourse-workflows/admin/components/workflows/canvas/canvas-file-io";
import WorkflowNode from "discourse/plugins/discourse-workflows/admin/models/workflow-node";

module("Unit | lib | discourse-workflows | canvas-file-io", function () {
  test("buildWorkflowExportPayload omits credential references", function (assert) {
    const node = WorkflowNode.create({
      clientId: "node-1",
      type: "action:http_request",
      type_version: "1.0",
      name: "Send request",
      configuration: {
        method: "GET",
        url: "https://example.com",
        authentication: "bearer_token",
        credentials: {
          auth: {
            id: "42",
            credential_type: "bearer_token",
          },
        },
      },
    });

    const payload = buildWorkflowExportPayload([node], [], []);

    assert.false("credentials" in payload.nodes[0]);
    assert.false("credentials" in payload.nodes[0].parameters);
  });

  test("parseWorkflowImport strips credential references", function (assert) {
    const result = parseWorkflowImport(
      JSON.stringify({
        version: 2,
        nodes: [
          {
            type: "action:http_request",
            type_version: "1.0",
            name: "Send request",
            parameters: {
              method: "GET",
              url: "https://example.com",
              authentication: "bearer_token",
              credentials: {
                auth: {
                  id: "99",
                  credential_type: "bearer_token",
                },
              },
            },
            credentials: {
              auth: {
                id: "42",
                credential_type: "bearer_token",
              },
            },
            settings: {
              credentials: {
                auth: {
                  id: "100",
                  credential_type: "bearer_token",
                },
              },
            },
          },
        ],
        connections: [],
      })
    );

    assert.deepEqual(result.nodes[0].credentials, {});
    assert.false("credentials" in result.nodes[0].parameters);
    assert.false("credentials" in result.nodes[0].settings);
    assert.false("credentials" in result.nodes[0].configuration);
  });
});
