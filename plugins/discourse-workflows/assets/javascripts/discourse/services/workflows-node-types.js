import { tracked } from "@glimmer/tracking";
import Service from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";

function sortForStableStringify(value) {
  if (Array.isArray(value)) {
    return value.map(sortForStableStringify);
  }

  if (value && typeof value === "object") {
    return Object.keys(value)
      .sort()
      .reduce((result, key) => {
        result[key] = sortForStableStringify(value[key]);
        return result;
      }, {});
  }

  return value;
}

function stableStringify(value) {
  return JSON.stringify(sortForStableStringify(value));
}

function compactObject(object) {
  return Object.fromEntries(
    Object.entries(object).filter(([, value]) => value !== undefined)
  );
}

function normalizeNodeForLoadOptions(node, identifier, typeVersion) {
  return compactObject({
    id: node?.clientId || node?.id,
    name: node?.name,
    type: node?.type || identifier,
    type_version: node?.type_version || typeVersion,
  });
}

export default class WorkflowsNodeTypes extends Service {
  @tracked nodeTypes = null;
  @tracked credentialTypes = null;
  @tracked expressionContext = {};

  // Graph context for the currently-editing node. Set by the editor
  // when the configurator modal opens, read by VariableInput to build
  // CodeMirror completion scope without prop drilling.
  @tracked editingNode = null;
  @tracked graphNodes = null;
  @tracked graphConnections = null;
  @tracked workflowVars = null;
  @tracked workflowId = null;
  @tracked lastExecutionNodeOutputs = null;

  nodeTypeMap = new Map();
  _nodeParameterOptionsCache = new Map();

  async load() {
    if (this.nodeTypes) {
      return this.nodeTypes;
    }

    try {
      const result = await ajax(
        "/admin/plugins/discourse-workflows/node-types.json"
      );
      this.nodeTypes = result.node_types || [];
      this.credentialTypes = result.credential_types || [];
      this.expressionContext = result.expression_context || {};
      this.nodeTypeMap = new Map(
        this.nodeTypes.flatMap((nt) => [
          [nt.name, nt],
          [nt.identifier, nt],
        ])
      );
      return this.nodeTypes;
    } catch (e) {
      popupAjaxError(e);
      return [];
    }
  }

  findNodeType(identifier) {
    return this.nodeTypeMap.get(identifier) || null;
  }

  async loadNodeParameterOptions(
    identifier,
    methodName,
    typeVersion = null,
    context = {}
  ) {
    const requestPayload = this.buildNodeParameterOptionsPayload({
      identifier,
      methodName,
      typeVersion,
      ...context,
    });
    const cacheKey = stableStringify({
      identifier,
      typeVersion: typeVersion || "latest",
      methodName,
      payload: requestPayload,
    });
    if (this._nodeParameterOptionsCache.has(cacheKey)) {
      return this._nodeParameterOptionsCache.get(cacheKey);
    }

    try {
      const result = await ajax(
        "/admin/plugins/discourse-workflows/dynamic-node-parameters/options.json",
        {
          type: "POST",
          contentType: "application/json",
          data: JSON.stringify(requestPayload),
        }
      );
      const options = result || [];
      this._nodeParameterOptionsCache.set(cacheKey, options);
      return options;
    } catch (e) {
      popupAjaxError(e);
      return [];
    }
  }

  buildNodeParameterOptionsPayload({
    identifier,
    methodName,
    typeVersion = null,
    path = null,
    currentNodeParameters = null,
    credentials = null,
    node = null,
    filter = null,
    inputContext = null,
    executionContext = null,
  } = {}) {
    const resolvedNode = node || this.editingNode;
    const resolvedVersion = typeVersion || resolvedNode?.type_version;

    return compactObject({
      path,
      nodeTypeAndVersion: compactObject({
        name: identifier,
        version: resolvedVersion,
      }),
      currentNodeParameters: currentNodeParameters || {},
      methodName,
      credentials: credentials || {},
      filter,
      node: normalizeNodeForLoadOptions(
        resolvedNode,
        identifier,
        resolvedVersion
      ),
      workflowId: this.workflowId,
      inputContext:
        inputContext === null
          ? this.inputContextForNode(resolvedNode)
          : inputContext,
      executionContext:
        executionContext === null
          ? this.executionContextForNode(resolvedNode)
          : executionContext,
    });
  }

  inputContextForNode(node = this.editingNode) {
    if (!node || !this.lastExecutionNodeOutputs) {
      return {
        available: false,
        reason: "No editor execution preview is available for this node",
      };
    }

    const incomingConnections = (this.graphConnections || []).filter(
      (connection) => connection.targetClientId === node.clientId
    );
    const sourceNodeOutputs = Object.fromEntries(
      incomingConnections
        .map((connection) => [
          connection.sourceClientId,
          this.lastExecutionNodeOutputs[connection.sourceClientId],
        ])
        .filter(([, output]) => output !== undefined)
    );

    if (Object.keys(sourceNodeOutputs).length === 0) {
      return {
        available: false,
        reason:
          "No upstream execution preview output is available for this node",
      };
    }

    return {
      available: true,
      source_node_outputs: sourceNodeOutputs,
    };
  }

  executionContextForNode(node = this.editingNode) {
    const currentNodeOutput = node
      ? this.lastExecutionNodeOutputs?.[node.clientId]
      : undefined;

    return compactObject({
      last_node_outputs: this.lastExecutionNodeOutputs || {},
      current_node_output: currentNodeOutput,
    });
  }

  setEditingContext(node, nodes, connections, { workflowId } = {}) {
    this.editingNode = node;
    this.graphNodes = nodes;
    this.graphConnections = connections;
    this.workflowId = workflowId;
  }

  async loadWorkflowVars() {
    if (this.workflowVars) {
      return this.workflowVars;
    }

    try {
      const result = await ajax(
        "/admin/plugins/discourse-workflows/variables.json"
      );
      this.workflowVars = result.variables || [];
    } catch {
      this.workflowVars = [];
    }
    return this.workflowVars;
  }

  invalidateWorkflowVars() {
    this.workflowVars = null;
  }

  clearEditingContext() {
    this.editingNode = null;
    this.graphNodes = null;
    this.graphConnections = null;
    this.workflowId = null;
    this.lastExecutionNodeOutputs = null;
  }

  clear() {
    this.nodeTypes = null;
    this.credentialTypes = null;
    this.expressionContext = {};
    this.nodeTypeMap = new Map();
    this._nodeParameterOptionsCache = new Map();
    this.invalidateWorkflowVars();
    this.workflowId = null;
    this.lastExecutionNodeOutputs = null;
    this.clearEditingContext();
  }
}
