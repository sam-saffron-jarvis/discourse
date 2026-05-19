import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { modifier } from "ember-modifier";
import Form from "discourse/components/form";
import { eq, or } from "discourse/truth-helpers";
import DButton from "discourse/ui-kit/d-button";
import DConditionalLoadingSpinner from "discourse/ui-kit/d-conditional-loading-spinner";
import DModal from "discourse/ui-kit/d-modal";
import dConcatClass from "discourse/ui-kit/helpers/d-concat-class";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import { i18n } from "discourse-i18n";
import {
  nodeTypeDescription,
  nodeTypeIcon,
  nodeTypeLabel,
  nodeTypeStyle,
  resolveNodeTypeVersion,
} from "../../../lib/workflows/node-types";
import {
  credentialSlotAnchorField,
  credentialSlotVisible,
  credentialTypesForSlot,
  fieldType,
  findNodeType,
  getPropertySchema,
} from "../../../lib/workflows/property-engine";
import CredentialControl from "../configurators/credential";
import PropertyEngineConfigurator from "../configurators/property-engine";
import InputContext from "../context/input";
import OutputContext from "../context/output";

const JS_TYPE_MAP = {
  number: "integer",
  boolean: "boolean",
  object: "object",
};

function inferFieldType(value) {
  if (Array.isArray(value)) {
    return "array";
  }
  if (value !== null && value !== undefined) {
    return JS_TYPE_MAP[typeof value] || "string";
  }
  return "string";
}

function credentialSlotLabel(slot) {
  return i18n(slot.label_key || "discourse_workflows.credentials.type");
}

function normalizeCredentials(credentials = {}) {
  return Object.fromEntries(
    Object.entries(credentials || {}).filter(([, value]) => value?.id)
  );
}

export default class NodeConfigurator extends Component {
  @service workflowsNodeTypes;

  @tracked nodeName = this.args.model.node.name || "";
  @tracked isEditingName = false;
  @tracked nodeTypes = null;
  @tracked activeTab = "parameters";
  @tracked
  settingsFormData = {
    description: this.args.model.node.configuration?.description || "",
  };

  @tracked credentialConfig = structuredClone(
    normalizeCredentials(
      this.args.model.node.configuration?.credentials ||
        this.args.model.node.credentials
    )
  );
  initialConfiguration = structuredClone(
    this.args.model.node.configuration || {}
  );

  parametersApi = null;

  focusNameInput = modifier((element) => {
    element.focus();
    element.select();
  });

  focusModal = modifier((element) => {
    requestAnimationFrame(() => {
      element.closest(".d-modal")?.querySelector(".btn")?.focus();
    });
  });

  constructor() {
    super(...arguments);
    this.#loadTypes();
  }

  get isLoading() {
    return this.nodeTypes === null;
  }

  get resolvedNodeType() {
    return resolveNodeTypeVersion(
      findNodeType(this.nodeTypes, this.args.model.node.type),
      this.args.model.node.type_version
    );
  }

  async #loadTypes() {
    this.nodeTypes = await this.workflowsNodeTypes.load();
    this.#applyDefaults();
  }

  #applyDefaults() {
    const config = this.initialConfiguration;

    for (const [key, fs] of Object.entries(this.propertySchema)) {
      if (config[key] != null) {
        continue;
      }
      if (fs.default !== undefined) {
        config[key] = fs.default;
      } else if (
        fieldType(fs) === "collection" ||
        fieldType(fs) === "fixed_collection"
      ) {
        config[key] = {};
      } else if (fieldType(fs) === "assignment_collection") {
        config[key] = { assignments: [] };
      } else if (fieldType(fs) === "array") {
        config[key] = [];
      }
    }

    const dataTableId = parseInt(config.data_table_id, 10);
    const dataTable = dataTableId
      ? findNodeType(
          this.nodeTypes,
          this.args.model.node.type
        )?.metadata?.data_tables?.find((dt) => dt.id === dataTableId)
      : null;
    if (dataTable) {
      config.output_fields = (dataTable.columns ?? []).map((column) => ({
        key: column.name,
        type: { number: "number", boolean: "boolean" }[column.type] ?? "string",
      }));
    }
  }

  get executionOutputFields() {
    const node = this.args.model.node;
    const schema = this.propertySchema?.output_fields;
    if (!schema?.ui?.hidden) {
      return null;
    }

    const json =
      this.workflowsNodeTypes.lastExecutionNodeOutputs?.[node.clientId];
    if (!json || typeof json !== "object") {
      return null;
    }

    return Object.entries(json).map(([key, value]) => ({
      key,
      type: inferFieldType(value),
    }));
  }

  get nodeTypeDefaultName() {
    return nodeTypeLabel(this.resolvedNodeType);
  }

  get nodeDescription() {
    return nodeTypeDescription(this.resolvedNodeType);
  }

  get propertySchema() {
    return getPropertySchema(
      this.nodeTypes,
      this.args.model.node.type,
      this.args.model.node.type_version
    );
  }

  get hasConfiguration() {
    return (
      Object.keys(this.propertySchema).length > 0 ||
      this.credentialSlots.length > 0
    );
  }

  get credentialSlots() {
    return this.resolvedNodeType?.credentials || [];
  }

  get unanchoredCredentialSlots() {
    return this.credentialSlots.filter(
      (slot) => !credentialSlotAnchorField(slot)
    );
  }

  get isUnavailable() {
    const nodeType = this.resolvedNodeType;
    return nodeType?.available === false;
  }

  get unavailableReasonKey() {
    return this.resolvedNodeType?.unavailable_reason_key;
  }

  @action
  switchTab(tab) {
    if (tab === "settings") {
      this.settingsFormData = {
        description: this.configuration.description || "",
      };
    }
    this.activeTab = tab;
  }

  @action
  registerParametersApi(api) {
    this.parametersApi = api;
  }

  @action
  handleDescriptionSet(value, { set, name }) {
    set(name, value);
    this.parametersApi?.set("description", value);
  }

  @action
  handleCredentialSet(slotName, value) {
    const credentials = { ...this.credentialConfig };
    if (value?.id) {
      credentials[slotName] = value;
    } else {
      delete credentials[slotName];
    }
    this.credentialConfig = credentials;
  }

  @action
  credentialValue(slotName) {
    return this.credentialConfig[slotName];
  }

  @action
  startEditingName() {
    this.isEditingName = true;
  }

  @action
  updateNodeName(event) {
    this.nodeName = event.target.value;
  }

  @action
  finishEditingName() {
    this.isEditingName = false;
  }

  @action
  handleNameKeydown(event) {
    if (event.key === "Enter") {
      event.preventDefault();
      event.target.blur();
    }
  }

  get configuration() {
    if (!this.parametersApi) {
      return this.initialConfiguration;
    }

    const config = {};
    for (const key of [...Object.keys(this.propertySchema), "description"]) {
      const value = this.parametersApi.get(key);
      if (value !== undefined) {
        config[key] = value;
      }
    }

    const executionFields = this.executionOutputFields;
    if (executionFields?.length) {
      config.output_fields = executionFields;
    }

    config.credentials = this.credentialConfig;

    return config;
  }

  get isDirty() {
    const formDirty = this.parametersApi?.isDirty ?? false;
    const nameDirty = this.nodeName !== (this.args.model.node.name || "");
    const credentialsDirty =
      JSON.stringify(normalizeCredentials(this.args.model.node.credentials)) !==
      JSON.stringify(this.credentialConfig);
    return formDirty || nameDirty || credentialsDirty;
  }

  @action
  handleClose() {
    if (this.isDirty) {
      this.args.model.onSave(this.configuration, this.nodeName);
    }
    this.args.closeModal();
    this.workflowsNodeTypes.clearEditingContext();
  }

  <template>
    <DModal
      @closeModal={{this.handleClose}}
      @submitOnEnter={{false}}
      @hideHeader={{true}}
      class="workflows-configurator-modal"
    >
      <:body>
        <div class="workflows-configurator-modal__header" {{this.focusModal}}>
          {{#if (nodeTypeIcon this.resolvedNodeType)}}
            <span
              class="workflows-configurator-modal__node-icon"
              style={{nodeTypeStyle this.resolvedNodeType}}
            >
              {{dIcon (nodeTypeIcon this.resolvedNodeType)}}
            </span>
          {{/if}}
          {{#if this.isEditingName}}
            <input
              type="text"
              value={{this.nodeName}}
              class="workflows-configurator-modal__name-input"
              {{this.focusNameInput}}
              {{on "input" this.updateNodeName}}
              {{on "blur" this.finishEditingName}}
              {{on "keydown" this.handleNameKeydown}}
            />
          {{else}}
            {{! eslint-disable ember/template-no-invalid-interactive }}
            <div
              class="workflows-configurator-modal__name"
              {{on "click" this.startEditingName}}
            >{{this.nodeName}}</div>
          {{/if}}
          <DButton
            @action={{this.handleClose}}
            @icon="xmark"
            class="btn-flat workflows-configurator-modal__close"
          />
        </div>
        <DConditionalLoadingSpinner @condition={{this.isLoading}}>
          {{#if this.isUnavailable}}
            <div class="workflows-configurator-modal__unavailable-banner">
              {{dIcon "triangle-exclamation"}}
              <span>{{i18n
                  (or
                    this.unavailableReasonKey
                    "discourse_workflows.node_unavailable.default"
                  )
                }}</span>
            </div>
          {{/if}}
          <div
            class={{dConcatClass
              "workflows-configurator-modal__columns"
              (if this.isUnavailable "is-unavailable")
            }}
          >
            <div class="workflows-configurator-modal__column --left">
              <InputContext
                @node={{@model.node}}
                @nodes={{@model.nodes}}
                @connections={{@model.connections}}
                @triggerType={{@model.triggerType}}
                @nodeTypes={{this.nodeTypes}}
                @hasConfiguration={{this.hasConfiguration}}
              />
            </div>

            <div class="workflows-configurator-modal__column --center">
              <div class="workflows-configurator__tabs">
                <button
                  type="button"
                  class={{dConcatClass
                    "workflows-configurator__tab"
                    (if (eq this.activeTab "parameters") "is-active")
                  }}
                  {{on "click" (fn this.switchTab "parameters")}}
                >{{i18n
                    "discourse_workflows.configurator.tabs.parameters"
                  }}</button>
                <button
                  type="button"
                  class={{dConcatClass
                    "workflows-configurator__tab"
                    (if (eq this.activeTab "settings") "is-active")
                  }}
                  {{on "click" (fn this.switchTab "settings")}}
                >{{i18n
                    "discourse_workflows.configurator.tabs.settings"
                  }}</button>
              </div>

              {{#if this.hasConfiguration}}
                <Form
                  @data={{this.initialConfiguration}}
                  @onRegisterApi={{this.registerParametersApi}}
                  @validateOn="change"
                  class="workflows-configurator-form
                    {{unless (eq this.activeTab 'parameters') 'is-hidden'}}"
                  as |form transientData|
                >
                  <PropertyEngineConfigurator
                    @form={{form}}
                    @formApi={{this.parametersApi}}
                    @configuration={{transientData}}
                    @nodeType={{@model.node.type}}
                    @schema={{this.propertySchema}}
                    @credentials={{this.credentialConfig}}
                    @credentialSlots={{this.credentialSlots}}
                    @credentialValue={{this.credentialValue}}
                    @onCredentialSet={{this.handleCredentialSet}}
                    @triggerType={{@model.triggerType}}
                    @node={{@model.node}}
                    @nodeParameters={{transientData}}
                    @nodes={{@model.nodes}}
                    @connections={{@model.connections}}
                    @nodeTypes={{this.nodeTypes}}
                  />
                  {{#each this.unanchoredCredentialSlots as |slot|}}
                    {{#if (credentialSlotVisible slot transientData)}}
                      <CredentialControl
                        @credentialTypes={{credentialTypesForSlot slot}}
                        @label={{credentialSlotLabel slot}}
                        @onChange={{fn this.handleCredentialSet slot.name}}
                        @value={{this.credentialValue slot.name}}
                      />
                    {{/if}}
                  {{/each}}
                </Form>
              {{else if (eq this.activeTab "parameters")}}
                <p>{{i18n
                    "discourse_workflows.configurator.no_configuration"
                  }}</p>
              {{/if}}

              {{#if (eq this.activeTab "settings")}}
                <Form
                  @data={{this.settingsFormData}}
                  class="workflows-configurator-form"
                  as |form|
                >
                  <form.Field
                    @name="description"
                    @title={{i18n
                      "discourse_workflows.configurator.description"
                    }}
                    @type="textarea"
                    @format="full"
                    @onSet={{this.handleDescriptionSet}}
                    as |field|
                  >
                    <field.Control
                      placeholder={{i18n
                        "discourse_workflows.configurator.description_placeholder"
                      }}
                    />
                  </form.Field>
                </Form>
                {{#if this.nodeDescription}}
                  <div class="workflows-configurator-modal__node">
                    <span class="workflows-configurator-modal__node-title">
                      {{#if (nodeTypeIcon this.resolvedNodeType)}}
                        <span
                          class="workflows-configurator-modal__node-icon"
                          style={{nodeTypeStyle this.resolvedNodeType}}
                        >
                          {{dIcon (nodeTypeIcon this.resolvedNodeType)}}
                        </span>
                      {{/if}}{{this.nodeTypeDefaultName}}
                    </span>
                    <p class="workflows-configurator-modal__node-description">
                      {{this.nodeDescription}}
                    </p>
                    <span class="workflows-configurator-modal__node-version">
                      v{{@model.node.type_version}}
                    </span>
                  </div>
                {{/if}}
              {{/if}}
            </div>

            <div class="workflows-configurator-modal__column --right">
              <OutputContext
                @node={{@model.node}}
                @nodes={{@model.nodes}}
                @connections={{@model.connections}}
                @triggerType={{@model.triggerType}}
                @nodeTypes={{this.nodeTypes}}
                @configuration={{this.configuration}}
              />
            </div>
          </div>
        </DConditionalLoadingSpinner>
      </:body>
    </DModal>
  </template>
}
