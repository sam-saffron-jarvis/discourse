import { module, test } from "qunit";
import WorkflowsIndex from "discourse/plugins/discourse-workflows/admin/components/workflows";

module("Unit | Component | workflows index", function () {
  test("status label calls out published workflows with draft changes", function (assert) {
    const component = Object.create(WorkflowsIndex.prototype);
    const workflow = {
      published_version_id: 1,
      has_unpublished_changes: true,
    };

    assert.strictEqual(
      component.workflowStatusLabel(workflow),
      "discourse_workflows.unpublished_changes"
    );
    assert.strictEqual(
      component.workflowStatusClass(workflow),
      "is-unpublished-changes"
    );
  });

  test("status label keeps published and unpublished states distinct", function (assert) {
    const component = Object.create(WorkflowsIndex.prototype);

    assert.strictEqual(
      component.workflowStatusLabel({ published_version_id: 1 }),
      "discourse_workflows.published"
    );
    assert.strictEqual(
      component.workflowStatusClass({ published_version_id: 1 }),
      "is-published"
    );
    assert.strictEqual(
      component.workflowStatusLabel({ published_version_id: null }),
      "discourse_workflows.unpublished"
    );
    assert.strictEqual(
      component.workflowStatusClass({ published_version_id: null }),
      "is-unpublished"
    );
  });
});
