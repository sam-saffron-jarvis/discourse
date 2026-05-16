import {
  normalizeSourceOutputIndex,
  normalizeTargetInputIndex,
  portIndexFromKey,
} from "../lib/workflows/graph-constants";

export default class WorkflowConnection {
  static create(args = {}) {
    return new WorkflowConnection(args);
  }

  static serialize(connection) {
    return {
      source_client_id: connection.sourceClientId,
      target_client_id: connection.targetClientId,
      connection_type: connection.connectionType || "main",
      source_output_index: normalizeSourceOutputIndex(connection),
      target_input_index: normalizeTargetInputIndex(connection),
    };
  }

  constructor(args = {}) {
    this.sourceClientId =
      args.sourceClientId ?? args.source_node_id?.toString();
    this.targetClientId =
      args.targetClientId ?? args.target_node_id?.toString();
    this.sourceOutput = args.sourceOutput ?? "main";
    this.targetInput = args.targetInput ?? "main";
    this.connectionType = args.connectionType ?? args.connection_type ?? "main";
    this.sourceOutputIndex =
      args.sourceOutputIndex ??
      args.source_output_index ??
      portIndexFromKey(this.sourceOutput);
    this.targetInputIndex =
      args.targetInputIndex ??
      args.target_input_index ??
      portIndexFromKey(this.targetInput);
  }
}
