import {
  normalizeSourceOutputIndex,
  normalizeTargetInputIndex,
} from "../../../lib/workflows/graph-constants";
import StickyNote, { STICKY_NOTE_TYPE } from "../../../models/sticky-note";
import WorkflowNode from "../../../models/workflow-node";

function stripCredentials(serialized) {
  delete serialized.credentials;
  return serialized;
}

function sanitizeImportedObject(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return {};
  }

  const sanitized = structuredClone(value);
  delete sanitized.credentials;
  return sanitized;
}

export function buildWorkflowExportPayload(nodes, connections, stickyNotes) {
  const exportedNodes = (nodes || []).map((n) => {
    const serialized = WorkflowNode.serialize(n);
    delete serialized.client_id;
    return stripCredentials(serialized);
  });

  const exportedStickyNotes = (stickyNotes || []).map((n) => {
    const serialized = StickyNote.serialize(n);
    delete serialized.client_id;
    return stripCredentials(serialized);
  });

  const allNodes = [...exportedNodes, ...exportedStickyNotes];

  const clientIdToIndex = new Map((nodes || []).map((n, i) => [n.clientId, i]));

  const exportedConnections = (connections || [])
    .filter(
      (c) =>
        clientIdToIndex.has(c.sourceClientId) &&
        clientIdToIndex.has(c.targetClientId)
    )
    .map((c) => ({
      source_index: clientIdToIndex.get(c.sourceClientId),
      target_index: clientIdToIndex.get(c.targetClientId),
      connection_type: c.connectionType || "main",
      source_output_index: normalizeSourceOutputIndex(c),
      target_input_index: normalizeTargetInputIndex(c),
    }));

  return {
    version: 2,
    nodes: allNodes,
    connections: exportedConnections,
  };
}

export function exportWorkflowToFile(nodes, connections, stickyNotes) {
  const payload = buildWorkflowExportPayload(nodes, connections, stickyNotes);
  const data = JSON.stringify(payload, null, 2);
  const date = new Date().toISOString().slice(0, 10);
  const file = new File([data], `workflow-nodes-${date}.json`, {
    type: "application/json",
  });

  const url = URL.createObjectURL(file);
  const a = document.createElement("a");
  a.href = url;
  a.download = file.name;
  a.click();
  URL.revokeObjectURL(url);
}

export function parseWorkflowImport(text) {
  const data = JSON.parse(text);

  if (!data || typeof data.version !== "number") {
    return { error: "invalid" };
  }

  if (data.version !== 2) {
    return { error: "version" };
  }

  if (!Array.isArray(data.nodes) || data.nodes.length === 0) {
    return { error: "invalid" };
  }

  const allImportedNodes = data.nodes.map((n) =>
    WorkflowNode.create({
      clientId: crypto.randomUUID(),
      type: n.type,
      type_version: n.type_version,
      name: n.name,
      parameters: sanitizeImportedObject(n.parameters),
      credentials: {},
      settings: sanitizeImportedObject(n.settings),
      webhook_id: n.webhook_id || null,
      position: n.position || null,
    })
  );

  const regularNodes = allImportedNodes.filter(
    (n) => n.type !== STICKY_NOTE_TYPE
  );

  const newStickyNotes = allImportedNodes
    .filter((n) => n.type === STICKY_NOTE_TYPE)
    .map((n) =>
      StickyNote.create({
        position: n.position,
        size: {
          width: n.parameters?.width,
          height: n.parameters?.height,
        },
        color: n.parameters?.color,
        text: n.parameters?.content,
      })
    );

  if (Array.isArray(data.sticky_notes)) {
    data.sticky_notes.forEach((n) => {
      newStickyNotes.push(StickyNote.create(n));
    });
  }

  const newConnections = (data.connections || [])
    .filter(
      (c) =>
        c.source_index >= 0 &&
        c.source_index < regularNodes.length &&
        c.target_index >= 0 &&
        c.target_index < regularNodes.length
    )
    .map((c) => ({
      sourceClientId: regularNodes[c.source_index].clientId,
      targetClientId: regularNodes[c.target_index].clientId,
      connectionType: c.connection_type || "main",
      sourceOutputIndex: normalizeSourceOutputIndex(c),
      targetInputIndex: normalizeTargetInputIndex(c),
    }));

  return {
    nodes: regularNodes,
    connections: newConnections,
    stickyNotes: newStickyNotes,
  };
}
