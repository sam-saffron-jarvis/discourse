import { resolveNodeTypeVersion } from "./node-types";
import { fieldVisible, fixedCollectionRows } from "./property-engine";

function formFieldKey(field) {
  if (field.field_name) {
    return field.field_name;
  }
  return (field.field_label ?? "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_|_$/g, "");
}

function toFieldEntry(key, type) {
  return { key, type: type || "string", id: key };
}

function fieldsFromConfig(configArray) {
  if (!configArray?.length) {
    return null;
  }
  return configArray
    .filter((f) => f.key)
    .map((f) => {
      const entry = toFieldEntry(f.key, f.type);
      if (f.children?.length) {
        entry.children = fieldsFromConfig(f.children);
      }
      return entry;
    });
}

const FORM_FIELD_TYPE_MAP = {
  number: "integer",
  checkbox: "boolean",
};

function fieldsFromFormFields(formFields) {
  const rows = fixedCollectionRows(formFields);
  if (!rows.length) {
    return null;
  }
  return [
    {
      key: "form_data",
      type: "object",
      id: "form_data",
      children: rows.map((f) =>
        toFieldEntry(
          formFieldKey(f),
          FORM_FIELD_TYPE_MAP[f.field_type] || "string"
        )
      ),
    },
    toFieldEntry("submitted_at", "string"),
  ];
}

function fieldsFromAssignments(assignments) {
  const rows = fixedCollectionRows(assignments, "assignments");
  if (!rows.length) {
    return null;
  }

  return rows
    .filter((assignment) => assignment.name)
    .map((assignment) =>
      toFieldEntry(
        assignment.name,
        {
          number: "number",
          boolean: "boolean",
          array: "array",
          object: "object",
        }[assignment.type] || "string"
      )
    );
}

export function fieldsFromSchema(outputSchema) {
  if (!outputSchema || !Object.keys(outputSchema).length) {
    return null;
  }
  return Object.entries(outputSchema).map(([key, value]) => {
    if (value && typeof value === "object" && !value.type) {
      return {
        key,
        type: "object",
        id: key,
        children: Object.entries(value).map(([childKey, childType]) =>
          toFieldEntry(childKey, childType)
        ),
      };
    }
    return toFieldEntry(key, value);
  });
}

export default function resolveNodeFields(
  node,
  nodeTypes,
  configuration = null
) {
  const config = configuration || node.configuration || {};
  const result =
    fieldsFromConfig(config.output_fields) ||
    fieldsFromAssignments(config.assignments);

  if (result) {
    return result;
  }

  const formFields = fieldsFromFormFields(config.form_fields);
  if (formFields) {
    return formFields;
  }

  const nodeType = nodeTypes.find(
    (nt) => nt.name === node.type || nt.identifier === node.type
  );
  const versionedNodeType = resolveNodeTypeVersion(nodeType, node.type_version);
  const schema =
    versionedNodeType?.outputSchema || versionedNodeType?.output_schema;
  if (!schema || !Object.keys(schema).length) {
    return null;
  }

  const filtered = {};
  for (const [key, value] of Object.entries(schema)) {
    if (typeof value === "object" && value !== null) {
      if (value.type) {
        if (fieldVisible(value, config)) {
          filtered[key] = value.fields || value.type;
        }
      } else {
        filtered[key] = value;
      }
    } else {
      filtered[key] = value;
    }
  }

  return fieldsFromSchema(filtered);
}
