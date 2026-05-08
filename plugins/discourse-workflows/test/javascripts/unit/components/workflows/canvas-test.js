import { setupTest } from "ember-qunit";
import { module, test } from "qunit";
import pretender, { response } from "discourse/tests/helpers/create-pretender";
import WorkflowCanvas from "discourse/plugins/discourse-workflows/admin/components/workflows/canvas";

module("Unit | Component | workflows canvas", function (hooks) {
  setupTest(hooks);

  test("autoLayout is defined on the prototype", function (assert) {
    assert.true(
      "autoLayout" in WorkflowCanvas.prototype,
      "autoLayout action exists"
    );
  });

  test("sync lifecycle entrypoints are defined on the prototype", function (assert) {
    assert.true(
      "registerCanvas" in WorkflowCanvas.prototype,
      "registerCanvas action exists"
    );
    assert.true(
      "registerContainer" in WorkflowCanvas.prototype,
      "registerContainer action exists"
    );
    assert.true(
      "syncToRete" in WorkflowCanvas.prototype,
      "syncToRete action exists"
    );
  });

  test("publish success clears optimistic unpublished changes override", async function (assert) {
    pretender.put("/admin/plugins/discourse-workflows/workflows/1.json", () =>
      response({})
    );

    const workflow = {
      draft_version_id: 2,
      published_version_id: 1,
      has_unpublished_changes: true,
    };

    const canvas = Object.create(WorkflowCanvas.prototype);
    Object.defineProperty(canvas, "args", {
      value: {
        workflow,
        workflowId: 1,
        workflowName: "Workflow",
        get workflowPublished() {
          return workflow.published_version_id;
        },
        get hasUnpublishedChanges() {
          return workflow.has_unpublished_changes;
        },
      },
    });

    await canvas.publishWorkflow();

    assert.true(canvas.publishDisabled, "publish is disabled after publish");

    workflow.has_unpublished_changes = true;

    assert.false(
      canvas.publishDisabled,
      "later draft edits can re-enable publish"
    );
  });
});
