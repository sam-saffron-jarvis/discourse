import moment from "moment";
import { i18n } from "discourse-i18n";
import {
  nodeTypePropertyI18nPrefix,
  nodeTypePropertyI18nScope,
  resolveNodeTypeVersion,
  translatedOrNull,
} from "./node-types";

function cloneValue(value) {
  return value === undefined ? undefined : structuredClone(value);
}

function humanize(value) {
  return value
    .toString()
    .replace(/_/g, " ")
    .replace(/\b\w/g, (char) => char.toUpperCase());
}

function fieldUi(schema = {}) {
  return schema.ui || {};
}

function fallbackValueForType(type) {
  switch (type) {
    case "boolean":
      return false;
    case "collection":
    case "fixed_collection":
      return {};
    case "assignment_collection":
      return { assignments: [] };
    case "array":
    case "multi_options":
      return [];
    default:
      return "";
  }
}

function translationKeyWithFallback(keys = []) {
  return keys.find((key) => translatedOrNull(key) !== null) || null;
}

export function findNodeType(nodeTypes, nodeType) {
  return (
    nodeTypes?.find(
      (definition) =>
        definition.name === nodeType || definition.identifier === nodeType
    ) || null
  );
}

export function getPropertySchema(nodeTypes, nodeType, typeVersion = null) {
  const definition = findNodeType(nodeTypes, nodeType);

  if (!definition) {
    return {};
  }

  const versionedDefinition = resolveNodeTypeVersion(definition, typeVersion);
  if (versionedDefinition?.properties || versionedDefinition?.property_schema) {
    return (
      versionedDefinition.properties || versionedDefinition.property_schema
    );
  }

  const versions =
    definition.property_versions || definition.property_schema_versions;

  if (typeVersion && versions?.[typeVersion]) {
    return versions[typeVersion];
  }

  return definition.properties || definition.property_schema || {};
}

export function normalizeSchema(schema = {}) {
  return Object.entries(schema).map(([name, field]) => ({
    name,
    ...field,
  }));
}

export function propertyI18nPrefix(nodeDefinitionOrType) {
  return nodeTypePropertyI18nPrefix(nodeDefinitionOrType);
}

export function propertyScope(nodeDefinitionOrType) {
  return nodeTypePropertyI18nScope(nodeDefinitionOrType);
}

function i18nBase(nodeDefinitionOrType) {
  return `${propertyI18nPrefix(nodeDefinitionOrType)}.${propertyScope(nodeDefinitionOrType)}`;
}

export function propertyLabel(nodeDefinitionOrType, fieldName) {
  const base = i18nBase(nodeDefinitionOrType);

  return (
    translatedOrNull(`${base}.${fieldName}`) ||
    translatedOrNull(`${base}.${fieldName}.title`) ||
    humanize(fieldName)
  );
}

export function propertyDescription(nodeDefinitionOrType, fieldName) {
  return translatedOrNull(
    `${i18nBase(nodeDefinitionOrType)}.${fieldName}_description`
  );
}

export function propertyPlaceholder(nodeDefinitionOrType, fieldName) {
  return translatedOrNull(
    `${i18nBase(nodeDefinitionOrType)}.${fieldName}_placeholder`
  );
}

export function propertySelectNoneKey(nodeDefinitionOrType, fieldName) {
  const base = i18nBase(nodeDefinitionOrType);
  const selectField = fieldName.replace(/_id$/, "");

  return translationKeyWithFallback([
    `${base}.select_${selectField}`,
    `${base}.${fieldName}_placeholder`,
  ]);
}

export function collectionAddLabel(
  nodeDefinitionOrType,
  fieldName,
  schema = {}
) {
  const override = fieldUi(schema).singular_name;
  const singular =
    override || (fieldName.endsWith("s") ? fieldName.slice(0, -1) : fieldName);

  return (
    translatedOrNull(`${i18nBase(nodeDefinitionOrType)}.add_${singular}`) ||
    i18n("discourse_workflows.property_engine.add_item")
  );
}

export function formatOptionValue(value, format) {
  if (format === "hour_of_day") {
    return moment().hour(value).minute(0).format("LT");
  }
  if (format === "weekday") {
    return moment().day(value).format("dddd");
  }
  return String(value);
}

export function normalizeOptions(options = []) {
  return options.map((option) =>
    typeof option === "object" ? option : { value: option }
  );
}

export function normalizePropertyOptions(options = []) {
  return options.map((option) => ({
    name: option.name || option.value,
    ...option,
  }));
}

export function fixedCollectionGroups(schema = {}) {
  return normalizePropertyOptions(schema.options || []);
}

export function fixedCollectionGroup(schema = {}) {
  return fixedCollectionGroups(schema)[0] || { name: "values", values: {} };
}

export function fixedCollectionGroupMultiple(group = {}, schema = {}) {
  const type_options = schema.type_options || {};
  if (Object.hasOwn(type_options, "multiple_values")) {
    return Boolean(type_options.multiple_values);
  }
  if (Object.hasOwn(group, "multiple_values")) {
    return Boolean(group.multiple_values);
  }
  return true;
}

export function fixedCollectionRows(value, groupName = "values") {
  if (Array.isArray(value)) {
    return value;
  }
  const groupValue = value?.[groupName];
  if (Array.isArray(groupValue)) {
    return groupValue;
  }
  if (groupValue && typeof groupValue === "object") {
    return [groupValue];
  }
  return [];
}

export function fieldType(schema = {}) {
  return schema.type || "string";
}

export function propertyOptionLabel(nodeDefinitionOrType, fieldName, option) {
  const base = i18nBase(nodeDefinitionOrType);

  return (
    translatedOrNull(`${base}.${fieldName}_${option.value}`) ||
    translatedOrNull(`${base}.${fieldName}s.${option.value}`) ||
    option.label ||
    option.name ||
    option.value
  );
}

const TYPE_TO_CONTROL = {
  boolean: "boolean",
  icon: "icon",
  options: "select",
  multi_options: "multi_combo_box",
  collection: "collection",
  fixed_collection: "fixed_collection",
  assignment_collection: "assignment_collection",
  notice: "notice",
  credential: "credential",
};

export function fieldControl(schema = {}) {
  return (
    fieldUi(schema).control || TYPE_TO_CONTROL[fieldType(schema)] || "input"
  );
}

export function fieldSupportsExpression(schema = {}) {
  const ui = fieldUi(schema);

  if (Object.hasOwn(ui, "expression")) {
    return Boolean(ui.expression);
  }

  return ["string", "integer", "number", "float", "icon"].includes(
    fieldType(schema)
  );
}

export function fieldShowDescription(schema = {}) {
  return fieldUi(schema).show_description !== false;
}

export function fieldShowLabel(schema = {}) {
  return fieldUi(schema).show_label !== false;
}

export function fieldFormat(schema = {}) {
  return fieldUi(schema).format || schema.format || "full";
}

export function fieldInputType(schema = {}) {
  const ui = fieldUi(schema);
  if (ui.control === "password") {
    return "password";
  }
  return ["integer", "float", "number"].includes(fieldType(schema))
    ? "number"
    : "text";
}

export function fieldValue(schema = {}, value) {
  return (
    value ??
    cloneValue(schema.default ?? fallbackValueForType(fieldType(schema)))
  );
}

export function emptyCollectionItem(itemSchema = {}, extraItemSchema = {}) {
  return Object.fromEntries(
    Object.entries({ ...itemSchema, ...extraItemSchema }).map(
      ([name, schema]) => [name, fieldValue(schema)]
    )
  );
}

export function emptyFixedCollectionItem(group = {}) {
  return emptyCollectionItem(group.values || {});
}

export function isExpression(value) {
  return typeof value === "string" && value.startsWith("=");
}

export function fieldVisible(schema = {}, configuration = {}) {
  if (fieldUi(schema).hidden) {
    return false;
  }

  const display_options = schema.display_options;
  if (
    display_options?.show &&
    !matchesRules(display_options.show, configuration)
  ) {
    return false;
  }
  if (
    display_options?.hide &&
    matchesRules(display_options.hide, configuration)
  ) {
    return false;
  }

  if (schema.visible_if && !matchesRules(schema.visible_if, configuration)) {
    return false;
  }

  if (
    schema.visible_unless &&
    matchesRules(schema.visible_unless, configuration)
  ) {
    return false;
  }

  return true;
}

function matchesRules(rules, configuration) {
  return Object.entries(rules).every(([fieldName, expected]) =>
    matchesRule(expected, configuration[fieldName])
  );
}

function matchesRule(expected, value) {
  if (expected === "$empty") {
    return isEmptyValue(value);
  }

  if (expected && typeof expected === "object" && !Array.isArray(expected)) {
    if (Object.hasOwn(expected, "empty")) {
      return expected.empty ? isEmptyValue(value) : !isEmptyValue(value);
    }
    if (Object.hasOwn(expected, "not")) {
      const notValues = Array.isArray(expected.not)
        ? expected.not
        : [expected.not];
      return !notValues.includes(value);
    }
    return false;
  }

  const allowedValues = Array.isArray(expected) ? expected : [expected];
  return allowedValues.includes(value);
}

function isEmptyValue(value) {
  if (value == null || value === "") {
    return true;
  }
  if (Array.isArray(value)) {
    return value.length === 0;
  }
  return false;
}
