import { module, test } from "qunit";
import { i18n } from "discourse-i18n";
import WorkflowsEditor from "discourse/plugins/discourse-workflows/admin/components/workflows/editor";

function buildEditor(workflow, dialog = {}) {
  const editor = Object.create(WorkflowsEditor.prototype);

  Object.defineProperty(editor, "args", {
    value: { workflow },
  });
  Object.defineProperty(editor, "dialog", {
    value: dialog,
  });

  return editor;
}

module("Unit | Component | workflows editor", function () {
  test("beforeunload warns when the workflow has an unpublished draft", function (assert) {
    const editor = buildEditor({ has_unpublished_changes: true });
    const event = {
      returnValue: null,
      preventDefault() {
        assert.step("prevented");
      },
    };

    const message = editor.handleBeforeUnload(event);

    assert.verifySteps(["prevented"]);
    assert.strictEqual(
      message,
      i18n("discourse_workflows.unpublished_changes_confirmation")
    );
    assert.strictEqual(event.returnValue, message);
  });

  test("beforeunload does not warn when the workflow has no unpublished draft", function (assert) {
    const editor = buildEditor({ has_unpublished_changes: false });
    const event = {
      preventDefault() {
        assert.true(false, "preventDefault should not be called");
      },
    };

    assert.strictEqual(editor.handleBeforeUnload(event), undefined);
  });

  test("beforeunload warns while a draft save is in flight", function (assert) {
    const editor = buildEditor({ has_unpublished_changes: false });
    const event = {
      returnValue: null,
      preventDefault() {
        assert.step("prevented");
      },
    };

    editor.saving = true;

    const message = editor.handleBeforeUnload(event);

    assert.verifySteps(["prevented"]);
    assert.strictEqual(
      message,
      i18n("discourse_workflows.unpublished_changes_confirmation")
    );
  });

  test("route changes ask for confirmation when the workflow has an unpublished draft", function (assert) {
    const transition = {
      isAborted: false,
      queryParamsOnly: false,
      from: { name: "adminPlugins.show.discourse-workflows.show.index" },
      to: { name: "adminPlugins.show.discourse-workflows" },
      abort() {
        assert.step("aborted");
      },
      retry() {
        assert.step("retried");
      },
    };
    const dialog = {
      confirm({ message, didConfirm }) {
        assert.strictEqual(
          message,
          i18n("discourse_workflows.unpublished_changes_confirmation")
        );
        didConfirm();
      },
    };
    const editor = buildEditor({ has_unpublished_changes: true }, dialog);

    editor.confirmUnpublishedDraftTransition(transition);

    assert.true(editor.allowUnpublishedDraftTransition);
    assert.verifySteps(["aborted", "retried"]);
  });
});
