const SETTINGS_PARAMETER_KEYS = ["description"];

function credentialTypeFor(configuration) {
  return ["basic_auth", "bearer_token"].includes(configuration.authentication)
    ? configuration.authentication
    : null;
}

function validCredentialType(credential) {
  return ["basic_auth", "bearer_token"].includes(credential?.credential_type);
}

function splitConfiguration(type, configuration = {}, existing = {}) {
  const parameters = structuredClone(configuration || {});
  const settings = structuredClone(existing.settings || {});
  const credentials = structuredClone(existing.credentials || {});
  let webhookId = existing.webhook_id || null;

  for (const key of SETTINGS_PARAMETER_KEYS) {
    if (Object.hasOwn(parameters, key)) {
      settings[key] = parameters[key];
      delete parameters[key];
    }
  }

  if (Object.hasOwn(parameters, "credential_id")) {
    const id = parameters.credential_id;
    const credentialType = credentialTypeFor(parameters);
    if (id && credentialType) {
      credentials.auth = {
        id: id.toString(),
        field_name: "credential_id",
        credential_type: credentialType,
      };
    } else {
      delete credentials.auth;
    }
    delete parameters.credential_id;
  } else if (Object.hasOwn(parameters, "authentication")) {
    const credentialType = credentialTypeFor(parameters);
    if (
      credentialType &&
      credentials.auth?.id &&
      credentials.auth?.field_name &&
      validCredentialType(credentials.auth)
    ) {
      credentials.auth.credential_type = credentialType;
    } else {
      delete credentials.auth;
    }
  } else {
    delete credentials.auth;
  }

  if (type === "trigger:form" && Object.hasOwn(parameters, "uuid")) {
    webhookId = parameters.uuid || webhookId;
    delete parameters.uuid;
  }

  return { parameters, credentials, settings, webhook_id: webhookId };
}

function configurationFromNodeData({
  type,
  parameters = {},
  credentials = {},
  settings = {},
  webhook_id: webhookId,
}) {
  const configuration = {
    ...structuredClone(parameters || {}),
    ...structuredClone(settings || {}),
  };

  const authCredential = credentials?.auth;
  if (
    authCredential?.id &&
    authCredential.field_name &&
    validCredentialType(authCredential)
  ) {
    configuration[authCredential.field_name] = authCredential.id;
  }

  if (type === "trigger:form" && webhookId) {
    configuration.uuid = webhookId;
  }

  return configuration;
}

export default class WorkflowNode {
  static create(args = {}) {
    return new WorkflowNode(args);
  }

  static serialize(node) {
    const split = splitConfiguration(node.type, node.configuration, node);

    return {
      client_id: node.clientId,
      type: node.type,
      type_version: node.type_version,
      name: node.name,
      parameters: split.parameters,
      credentials: split.credentials,
      settings: split.settings,
      webhook_id: split.webhook_id,
      position: node.position || null,
    };
  }

  constructor(args = {}) {
    this.clientId = args.clientId ?? args.id?.toString() ?? crypto.randomUUID();
    this.type = args.type;
    this.type_version = args.type_version ?? "1.0";
    this.name = args.name;
    this.parameters = args.parameters ?? {};
    this.credentials = args.credentials ?? {};
    this.settings = args.settings ?? {};
    this.webhook_id = args.webhook_id ?? null;
    this.configuration =
      args.configuration ??
      configurationFromNodeData({
        type: this.type,
        parameters: this.parameters,
        credentials: this.credentials,
        settings: this.settings,
        webhook_id: this.webhook_id,
      });
    this.position = args.position ?? null;
  }
}
