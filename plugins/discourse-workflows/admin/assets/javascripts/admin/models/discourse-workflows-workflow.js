import { tracked } from "@glimmer/tracking";
import RestModel from "discourse/models/rest";
import StickyNote from "./sticky-note";
import WorkflowConnection from "./workflow-connection";
import WorkflowNode from "./workflow-node";

export default class DiscourseWorkflowsWorkflow extends RestModel {
  @tracked name;
  @tracked error_workflow_id;
  @tracked draft_version_id;
  @tracked published_version_id;
  @tracked has_unpublished_changes;
  @tracked last_execution_status;
  @tracked nodes = [];
  @tracked connections = [];

  updateProperties() {
    return {
      name: this.name,
      nodes: [
        ...this.nodes.map(WorkflowNode.serialize),
        ...(this.sticky_notes || []).map(StickyNote.serialize),
      ],
      connections: this.connections.map(WorkflowConnection.serialize),
    };
  }

  createProperties() {
    return this.updateProperties();
  }
}
