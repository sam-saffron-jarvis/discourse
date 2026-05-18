import { i18n } from "discourse-i18n";

export const WORKFLOW_VARIABLE_MIME = "application/x-workflow-variable";

const WORKFLOW_METHOD_DOCS = Object.freeze({
  $input: Object.freeze({
    all: Object.freeze({
      detail: "()",
      infoKey: "discourse_workflows.expression_docs.methods.input.all",
    }),
    first: Object.freeze({
      detail: "()",
      infoKey: "discourse_workflows.expression_docs.methods.input.first",
    }),
    last: Object.freeze({
      detail: "()",
      infoKey: "discourse_workflows.expression_docs.methods.input.last",
    }),
  }),
});

export function resolveVariableId(variable, itemPrefix = "$json") {
  return variable.id.startsWith("$")
    ? variable.id
    : `${itemPrefix}.${variable.id}`;
}

// Matches paths like $('Node Name').rest or $("Node Name").rest
const NODE_REF_RE = /^\$\((['"])(.*?)\1\)/;
const METHOD_CALL_RE = /^([A-Za-z_$][\w$]*)\((.*)\)$/;

export function walkScope(scope, path) {
  if (!path) {
    return undefined;
  }

  const nodeRef = NODE_REF_RE.exec(path);
  if (nodeRef) {
    const nodeName = nodeRef[2];
    const rest = path.slice(nodeRef[0].length);
    const parts = rest ? rest.slice(1).split(".") : []; // skip leading "."
    let target;
    try {
      target = scope.$(nodeName);
    } catch {
      return undefined;
    }
    for (const part of parts) {
      if (target == null) {
        return undefined;
      }
      target = resolvePathPart(target, part);
    }
    return target;
  }

  const parts = path.split(".");
  let target = scope[parts[0]];
  for (let i = 1; i < parts.length; i++) {
    if (target == null) {
      return undefined;
    }
    target = resolvePathPart(target, parts[i]);
  }
  return target;
}

function resolvePathPart(target, part) {
  const methodCall = METHOD_CALL_RE.exec(part);
  if (methodCall && typeof target[methodCall[1]] === "function") {
    return target[methodCall[1]](...parseMethodArgs(methodCall[2]));
  }

  return target[part];
}

function parseMethodArgs(source) {
  const args = source.trim();
  if (!args) {
    return [];
  }

  return args.split(",").map((arg) => {
    const value = arg.trim();
    if (/^-?\d+(\.\d+)?$/.test(value)) {
      return Number(value);
    }

    if (
      (value.startsWith("'") && value.endsWith("'")) ||
      (value.startsWith('"') && value.endsWith('"'))
    ) {
      return value.slice(1, -1);
    }

    return undefined;
  });
}

const TYPE_EXEMPLARS = {
  string: "",
  integer: 0,
  number: 0,
  boolean: false,
  array: [],
  object: {},
};

function cleanObject(obj) {
  const clean = Object.create(null);
  for (const [key, value] of Object.entries(obj)) {
    clean[key] = value;
  }
  return clean;
}

function buildItem(json) {
  return cleanObject({ json });
}

function buildNodeOutput(json) {
  const item = buildItem(json);
  const items = [item];

  return cleanObject({
    item,
    all: () => items,
    first: () => item,
    last: () => item,
    itemMatching: () => item,
    pairedItem: () => item,
    context: Object.create(null),
    params: Object.create(null),
  });
}

const EMPTY_NODE_OUTPUT = buildNodeOutput(Object.create(null));

export function lookupWorkflowMethodDoc(parentPath, methodName) {
  const doc = WORKFLOW_METHOD_DOCS[parentPath]?.[methodName];
  if (!doc) {
    return null;
  }
  return { detail: doc.detail, info: i18n(doc.infoKey) };
}

function buildScopeFromFields(fields) {
  if (!fields?.length) {
    return Object.create(null);
  }

  const obj = Object.create(null);
  for (const field of fields) {
    if (field.children?.length) {
      obj[field.key] = buildScopeFromFields(field.children);
    } else {
      obj[field.key] = TYPE_EXEMPLARS[field.type] ?? TYPE_EXEMPLARS.string;
    }
  }
  return obj;
}

function buildSiteSettingsScope(siteSettings) {
  if (!siteSettings) {
    return Object.create(null);
  }

  const scope = Object.create(null);
  for (const key of Object.keys(siteSettings)) {
    if (key.startsWith("_") || key.startsWith("theme")) {
      continue;
    }

    const value = siteSettings[key];
    const type = typeof value;

    if (type === "function" || type === "symbol") {
      continue;
    }

    scope[key] = value;
  }
  return scope;
}

function buildVarsScope(workflowVars) {
  const scope = Object.create(null);
  if (workflowVars?.length) {
    for (const v of workflowVars) {
      scope[v.key] = v.value ?? "";
    }
  }
  return scope;
}

function buildExecutionScope(nodes) {
  const scope = cleanObject({
    id: 0,
    workflow_id: 0,
    workflow_name: "",
  });

  const hasWebhookWait = (nodes || []).some(
    (n) => n.type === "flow:wait" && n.configuration?.resume === "webhook"
  );

  if (hasWebhookWait) {
    scope.resume_url = "";
  }

  const hasFormPage = (nodes || []).some(
    (n) =>
      n.type === "action:form" && n.configuration?.page_type !== "completion"
  );

  if (hasFormPage) {
    scope.resumeFormUrl = "";
  }

  return scope;
}

function buildInputScope($json) {
  const currentItem = buildItem($json);
  const inputItems = [currentItem];

  return cleanObject({
    item: currentItem,
    all: () => inputItems,
    first: () => currentItem,
    last: () => currentItem,
    params: Object.create(null),
    context: Object.create(null),
  });
}

export function buildScope({
  inputFields = [],
  ancestorNodes = [],
  siteSettings,
  workflowVars,
  nodes,
}) {
  const $json = buildScopeFromFields(inputFields);
  const $input = buildInputScope($json);

  const nodeOutputs = Object.create(null);
  for (const ancestor of ancestorNodes) {
    const json = buildScopeFromFields(ancestor.fields);
    nodeOutputs[ancestor.node.name] = buildNodeOutput(json);
  }

  return cleanObject({
    $input,
    $itemIndex: 0,
    $json,
    trigger: $json,
    $site_settings: buildSiteSettingsScope(siteSettings),
    $current_user: cleanObject({ id: 0, username: "" }),
    $vars: buildVarsScope(workflowVars),
    $execution: buildExecutionScope(nodes),
    $: (name) => nodeOutputs[name] || EMPTY_NODE_OUTPUT,
    JSON,
    Math,
    Object,
    Array,
    String,
    Number,
    Date,
    parseInt,
    parseFloat,
    encodeURIComponent,
    decodeURIComponent,
    isNaN,
    isFinite,
  });
}
