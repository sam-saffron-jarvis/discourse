import Component from "@glimmer/component";
import { fn } from "@ember/helper";
import { action } from "@ember/object";
import DButton from "discourse/components/d-button";
import DropdownMenu from "discourse/components/dropdown-menu";
import DMenu from "discourse/float-kit/components/d-menu";
import icon from "discourse/helpers/d-icon";
import { i18n } from "discourse-i18n";
import {
  fieldValue,
  findNodeType,
  normalizePropertyOptions,
  propertyDescription,
  propertyLabel,
} from "../../../lib/workflows/property-engine";
import Field from "./field";

export default class Collection extends Component {
  get nodeDefinition() {
    return (
      this.args.nodeDefinition ||
      findNodeType(this.args.nodeTypes, this.args.nodeType)
    );
  }

  get label() {
    return (
      this.args.label || propertyLabel(this.nodeDefinition, this.args.fieldName)
    );
  }

  get description() {
    return propertyDescription(this.nodeDefinition, this.args.fieldName);
  }

  get currentValue() {
    return this.args.formApi?.get(this.args.fieldName) || {};
  }

  get options() {
    return normalizePropertyOptions(this.args.schema.options || []);
  }

  get selectedOptions() {
    return this.options.filter((option) =>
      Object.hasOwn(this.currentValue, option.name)
    );
  }

  get availableOptions() {
    return this.options.filter(
      (option) => !Object.hasOwn(this.currentValue, option.name)
    );
  }

  get hasAvailableOptions() {
    return this.availableOptions.length > 0;
  }

  @action
  optionPath(name) {
    return `${this.args.fieldName}.${name}`;
  }

  @action
  optionLabel(option) {
    return (
      propertyLabel(this.nodeDefinition, option.name) ||
      option.display_name ||
      option.name
    );
  }

  @action
  addOption(option, close) {
    this.args.formApi.set(this.args.fieldName, {
      ...this.currentValue,
      [option.name]: fieldValue(option),
    });
    close?.();
  }

  @action
  removeOption(option) {
    const nextValue = { ...this.currentValue };
    delete nextValue[option.name];
    this.args.formApi.set(this.args.fieldName, nextValue);
  }

  <template>
    <@form.Section @title={{this.label}} @subtitle={{this.description}}>
      {{#each this.selectedOptions key="name" as |option|}}
        <div class="workflows-property-engine__collection-row">
          <div class="workflows-property-engine__collection-delete">
            <DButton
              @action={{fn this.removeOption option}}
              @icon="trash-can"
              class="btn-transparent btn-small btn-danger"
            />
          </div>

          <div class="workflows-property-engine__collection-fields">
            <Field
              @form={{@form}}
              @formApi={{@formApi}}
              @configuration={{this.currentValue}}
              @connections={{@connections}}
              @credentials={{@credentials}}
              @fieldName={{this.optionPath option.name}}
              @label={{this.optionLabel option}}
              @node={{@node}}
              @nodeDefinition={{this.nodeDefinition}}
              @nodeParameters={{@nodeParameters}}
              @nodeType={{@nodeType}}
              @nodes={{@nodes}}
              @nodeTypes={{@nodeTypes}}
              @schema={{option}}
            />
          </div>
        </div>
      {{/each}}

      {{#if this.hasAvailableOptions}}
        <DMenu
          class="btn btn-default workflows-property-engine__add-attrs-btn"
          @inline={{true}}
          @modalForwardRecipient={{true}}
        >
          <:trigger>
            {{i18n "discourse_workflows.property_engine.add_option"}}
            {{icon "chevron-down"}}
          </:trigger>
          <:content as |menu|>
            <DropdownMenu as |dropdown|>
              {{#each this.availableOptions key="name" as |option|}}
                <dropdown.item>
                  <DButton
                    class="btn-transparent"
                    @action={{fn this.addOption option menu.close}}
                    @translatedLabel={{this.optionLabel option}}
                  />
                </dropdown.item>
              {{/each}}
            </DropdownMenu>
          </:content>
        </DMenu>
      {{/if}}
    </@form.Section>
  </template>
}
