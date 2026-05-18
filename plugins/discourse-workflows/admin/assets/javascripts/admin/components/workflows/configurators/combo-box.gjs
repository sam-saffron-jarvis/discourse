import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { hash } from "@ember/helper";
import { action } from "@ember/object";
import { service } from "@ember/service";
import ComboBox from "discourse/select-kit/components/combo-box";
import {
  fieldType,
  formatOptionValue,
  normalizeOptions,
  propertyOptionLabel,
  propertySelectNoneKey,
} from "../../../lib/workflows/property-engine";
import ExpressionWrapper from "./expression-wrapper";

export class DynamicOptionsComboBox extends ComboBox {
  search(filter) {
    if (this.loadOptions) {
      return this.loadOptions(filter);
    }

    return super.search(filter);
  }
}

function optionValue(option, valueProperty) {
  return option[valueProperty] ?? option.id ?? option.value;
}

function optionName(option, nameProperty) {
  return option[nameProperty] ?? option.name ?? option.label;
}

export default class ComboBoxField extends Component {
  @service workflowsNodeTypes;

  @tracked _remoteOptions = [];
  _remoteOptionsRequestKey = null;

  constructor(owner, args) {
    super(owner, args);
    this.ensureRemoteOptions();
  }

  get methodName() {
    return this.args.schema?.type_options?.load_options_method;
  }

  get identifier() {
    return (
      this.args.nodeDefinition?.name || this.args.nodeDefinition?.identifier
    );
  }

  get typeVersion() {
    return this.args.nodeDefinition?.version || this.args.node?.type_version;
  }

  get localOptions() {
    return (
      this.args.metadata?.[this.methodName] ||
      this.args.nodeDefinition?.metadata?.[this.methodName]
    );
  }

  get usesRemoteOptions() {
    return Boolean(this.methodName && this.identifier && !this.localOptions);
  }

  get metadataOptions() {
    if (!this.methodName) {
      return null;
    }
    if (this.localOptions) {
      return this.localOptions;
    }
    this.ensureRemoteOptions();
    return this._remoteOptions;
  }

  get controlOptions() {
    return this.args.schema?.control_options || {};
  }

  get none() {
    return (
      this.controlOptions.none ||
      propertySelectNoneKey(this.args.nodeDefinition, this.args.fieldName)
    );
  }

  get filterable() {
    return Boolean(this.controlOptions.filterable);
  }

  get valueProperty() {
    return this.controlOptions.value_property || "id";
  }

  get nameProperty() {
    return this.controlOptions.name_property || "name";
  }

  get patchFromOption() {
    return this.controlOptions.patch_from_option || {};
  }

  get resets() {
    return this.controlOptions.resets || [];
  }

  get castInteger() {
    return fieldType(this.args.schema) === "integer";
  }

  get options() {
    if (this.metadataOptions) {
      return this.formatOptions(this.metadataOptions);
    }

    const optionFormat = this.controlOptions.option_format;
    return normalizeOptions(this.args.schema.options).map((option) => ({
      id: option.value,
      name: optionFormat
        ? formatOptionValue(option.value, optionFormat)
        : propertyOptionLabel(
            this.args.nodeDefinition,
            this.args.fieldName,
            option
          ),
      original: option,
    }));
  }

  formatOptions(options) {
    return options.map((option) => ({
      id: optionValue(option, this.valueProperty),
      name:
        optionName(option, this.nameProperty) ||
        optionValue(option, this.valueProperty),
      original: option,
    }));
  }

  remoteOptionsContext(filter = null) {
    return {
      path: this.args.fieldName,
      currentNodeParameters:
        this.args.nodeParameters || this.args.configuration || {},
      credentials: this.args.credentials || {},
      node: this.args.node,
      filter,
    };
  }

  remoteOptionsRequestKey(filter = null) {
    return JSON.stringify({
      methodName: this.methodName,
      identifier: this.identifier,
      typeVersion: this.typeVersion,
      context: this.remoteOptionsContext(filter),
    });
  }

  ensureRemoteOptions(filter = null) {
    if (!this.usesRemoteOptions) {
      return;
    }

    const requestKey = this.remoteOptionsRequestKey(filter);
    if (this._remoteOptionsRequestKey === requestKey) {
      return;
    }

    this._remoteOptionsRequestKey = requestKey;
    this.workflowsNodeTypes
      .loadNodeParameterOptions(
        this.identifier,
        this.methodName,
        this.typeVersion,
        this.remoteOptionsContext(filter)
      )
      .then((options) => {
        if (this._remoteOptionsRequestKey === requestKey) {
          this._remoteOptions = options;
        }
      });
  }

  @action
  async loadRemoteOptions(filter = null) {
    if (!this.usesRemoteOptions) {
      return null;
    }

    const options = await this.workflowsNodeTypes.loadNodeParameterOptions(
      this.identifier,
      this.methodName,
      this.typeVersion,
      this.remoteOptionsContext(filter)
    );
    this._remoteOptions = options;
    this._remoteOptionsRequestKey = this.remoteOptionsRequestKey(filter);

    return this.formatOptions(options);
  }

  @action
  handleChange(value) {
    this.args.field.set(value);

    const selectedOption = this.options.find(
      (option) => String(option.id) === String(value)
    );

    for (const [fieldName, propertyName] of Object.entries(
      this.patchFromOption
    )) {
      this.args.formApi?.set(
        fieldName,
        selectedOption?.original?.[propertyName] || ""
      );
    }

    const schema = this.args.nodeDefinition?.properties || {};
    for (const fieldName of this.resets) {
      const type = fieldType(schema[fieldName]);
      let resetValue = null;
      if (type === "array" || type === "collection") {
        resetValue = [];
      } else if (type === "object") {
        resetValue = {};
      }
      this.args.formApi?.set(fieldName, resetValue);
    }
  }

  <template>
    <ExpressionWrapper
      @field={{@field}}
      @supportsExpression={{@supportsExpression}}
      @placeholder={{@placeholder}}
    >
      <DynamicOptionsComboBox
        @content={{this.options}}
        @loadOptions={{if this.usesRemoteOptions this.loadRemoteOptions}}
        @nameProperty="name"
        @value={{@field.value}}
        @valueProperty="id"
        @onChange={{this.handleChange}}
        @options={{hash
          filterable=this.filterable
          none=this.none
          castInteger=this.castInteger
        }}
      />
    </ExpressionWrapper>
  </template>
}
