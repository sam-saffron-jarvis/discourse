import { setupTest } from "ember-qunit";
import { module, test } from "qunit";
import pretender, { response } from "discourse/tests/helpers/create-pretender";
import ComboBoxField from "discourse/plugins/discourse-workflows/admin/components/workflows/configurators/combo-box";
import {
  nodeTypeInputLabel,
  nodeTypeInputs,
  nodeTypeOperationLabel,
  nodeTypeOutputKeys,
  nodeTypePaletteGroup,
  nodeTypePortLabel,
  nodeTypePrimaryOutputKey,
  nodeTypePropertyI18nPrefix,
  nodeTypePropertyI18nScope,
  resolveNodeTypeVersion,
} from "discourse/plugins/discourse-workflows/admin/lib/workflows/node-types";

module("Unit | Utility | workflows node types", function () {
  test("reads property i18n metadata from the descriptor ui", function (assert) {
    const nodeType = {
      identifier: "action:ai_agent",
      ui: {
        property_i18n_prefix: "discourse_ai.discourse_workflows",
        property_i18n_scope: "ai_agent",
      },
    };

    assert.strictEqual(
      nodeTypePropertyI18nPrefix(nodeType),
      "discourse_ai.discourse_workflows"
    );
    assert.strictEqual(nodeTypePropertyI18nScope(nodeType), "ai_agent");
  });

  test("reads operation labels and palette groups from the descriptor", function (assert) {
    const nodeType = {
      identifier: "action:data_table",
      operations: [
        {
          value: "insert",
          label_key: "discourse_workflows.data_table_node.operations.insert",
        },
      ],
      ui: {
        palette_group: {
          id: "data",
          icon: "table",
          label_key: "discourse_workflows.add_node.categories.data",
          order: 50,
        },
      },
    };

    assert.strictEqual(nodeTypeOperationLabel(nodeType, "insert"), "Insert");
    assert.deepEqual(nodeTypePaletteGroup(nodeType), {
      id: "data",
      icon: "table",
      label_key: "discourse_workflows.add_node.categories.data",
      order: 50,
    });
  });

  test("uses descriptor ports for labels and routing", function (assert) {
    const filterNodeType = {
      identifier: "condition:filter",
      ports: [
        {
          key: "true",
          primary: true,
          label_key: "discourse_workflows.executions.statuses.kept",
        },
        {
          key: "false",
          primary: false,
          label_key: "discourse_workflows.executions.statuses.rejected",
        },
      ],
    };
    const loopNodeType = {
      identifier: "flow:loop_over_items",
      ports: [
        {
          key: "done",
          primary: true,
          label_key: "discourse_workflows.branch.done",
        },
        {
          key: "loop",
          primary: false,
          label_key: "discourse_workflows.branch.loop",
        },
      ],
    };

    assert.strictEqual(nodeTypePortLabel(filterNodeType, "true"), "Kept");
    assert.strictEqual(nodeTypePortLabel(filterNodeType, "false"), "Rejected");
    assert.strictEqual(nodeTypePrimaryOutputKey(loopNodeType), "done");
  });

  test("resolves a full node definition for a saved type version", function (assert) {
    const nodeType = {
      identifier: "action:versioned",
      latest_version: "2.0",
      latest: {
        identifier: "action:versioned",
        version: "2.0",
        outputs: [{ key: "new", primary: true }],
      },
      versions: {
        "1.0": {
          identifier: "action:versioned",
          version: "1.0",
          outputs: [{ key: "old", primary: true }],
        },
        "2.0": {
          identifier: "action:versioned",
          version: "2.0",
          outputs: [{ key: "new", primary: true }],
        },
      },
    };

    assert.strictEqual(resolveNodeTypeVersion(nodeType, "1.0").version, "1.0");
    assert.deepEqual(nodeTypeOutputKeys(nodeType, { type_version: "1.0" }), [
      "old",
    ]);
    assert.deepEqual(nodeTypeOutputKeys(nodeType), ["new"]);
  });

  test("uses merge mode configuration for input sockets", function (assert) {
    const mergeNodeType = {
      identifier: "flow:merge",
      inputs: [
        { key: "main" },
        { key: "input_1", required: true },
        { key: "input_2", required: true },
      ],
    };

    assert.deepEqual(
      nodeTypeInputs(mergeNodeType, {
        configuration: { mode: "append" },
      }).map((input) => input.key),
      ["input_1", "input_2"]
    );
    assert.deepEqual(
      nodeTypeInputs(mergeNodeType, {
        configuration: { mode: "append", number_inputs: 3 },
      }).map((input) => input.key),
      ["input_1", "input_2", "input_3"]
    );
    assert.deepEqual(
      nodeTypeInputs(mergeNodeType, {
        configuration: { mode: "combine" },
      }).map((input) => input.key),
      ["input_1", "input_2"]
    );
    assert.strictEqual(
      nodeTypeInputLabel(mergeNodeType, "input_1", {
        configuration: { mode: "combine" },
      }),
      "Input 1"
    );
  });
});

module("Unit | Service | workflows-node-types", function (hooks) {
  setupTest(hooks);

  test("buildLoadOptionsContext includes current node, parameters, credentials, and execution context", function (assert) {
    const service = this.owner.lookup("service:workflows-node-types");
    const node = {
      clientId: "node-1",
      name: "Group",
      type: "action:group",
      type_version: "1.0",
    };
    const upstreamOutput = [{ json: { username: "sam" } }];

    service.lastExecutionNodeOutputs = { "node-0": upstreamOutput };
    service.setEditingContext(
      node,
      [node],
      [{ sourceClientId: "node-0", targetClientId: "node-1" }],
      { workflowId: 7 }
    );

    const context = service.buildLoadOptionsContext({
      identifier: "action:group",
      typeVersion: "1.0",
      propertyName: "group_id",
      parameters: { operation: "get" },
      credentials: { auth: { id: "12", credential_type: "basic_auth" } },
      search: "staff",
    });

    assert.deepEqual(context.parameters, { operation: "get" });
    assert.deepEqual(context.credentials, {
      auth: { id: "12", credential_type: "basic_auth" },
    });
    assert.deepEqual(context.node, {
      id: "node-1",
      name: "Group",
      type: "action:group",
      type_version: "1.0",
    });
    assert.strictEqual(context.property_name, "group_id");
    assert.strictEqual(context.workflow_id, 7);
    assert.strictEqual(context.search, "staff");
    assert.strictEqual(context.filter, "staff");
    assert.deepEqual(context.input_context, {
      available: true,
      source_node_outputs: { "node-0": upstreamOutput },
    });
    assert.deepEqual(context.execution_context, {
      last_node_outputs: { "node-0": upstreamOutput },
    });
  });

  test("dynamic options use full node parameters even inside nested configurators", function (assert) {
    const component = Object.create(ComboBoxField.prototype);

    Object.defineProperty(component, "args", {
      value: {
        fieldName: "nested_group_id",
        configuration: { local: true },
        nodeParameters: { operation: "get", authentication: "basic_auth" },
        credentials: { auth: { id: "12", credential_type: "basic_auth" } },
        node: { clientId: "node-1", type: "action:group" },
      },
    });

    const context = component.remoteOptionsContext("staff");

    assert.deepEqual(context.parameters, {
      operation: "get",
      authentication: "basic_auth",
    });
    assert.deepEqual(context.credentials, {
      auth: { id: "12", credential_type: "basic_auth" },
    });
    assert.deepEqual(context.node, {
      clientId: "node-1",
      type: "action:group",
    });
    assert.strictEqual(context.propertyName, "nested_group_id");
    assert.strictEqual(context.search, "staff");
  });

  test("loadSourceOptions posts structured context and caches by context", async function (assert) {
    const requests = [];

    pretender.post(
      "/admin/plugins/discourse-workflows/node-types/action%3Agroup/options/groups.json",
      (request) => {
        const body = JSON.parse(request.requestBody);
        requests.push(body);

        return response({
          options: [{ id: requests.length, name: body.parameters.operation }],
        });
      }
    );

    const service = this.owner.lookup("service:workflows-node-types");
    const context = {
      parameters: { operation: "add" },
      search: "alp",
      node: { clientId: "node-1", name: "Group" },
    };

    const first = await service.loadSourceOptions(
      "action:group",
      "groups",
      "1.0",
      context
    );
    const second = await service.loadSourceOptions(
      "action:group",
      "groups",
      "1.0",
      context
    );
    const third = await service.loadSourceOptions(
      "action:group",
      "groups",
      "1.0",
      { ...context, parameters: { operation: "get" } }
    );

    assert.strictEqual(requests.length, 2);
    assert.deepEqual(second, first);
    assert.deepEqual(requests[0].parameters, { operation: "add" });
    assert.strictEqual(requests[0].search, "alp");
    assert.strictEqual(requests[0].filter, "alp");
    assert.deepEqual(requests[0].node, {
      id: "node-1",
      name: "Group",
      type: "action:group",
      type_version: "1.0",
    });
    assert.strictEqual(requests[0].version, "1.0");
    assert.strictEqual(third[0].name, "get");
  });
});
