import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn } from "@ember/helper";
import { action } from "@ember/object";
import DButton from "discourse/components/d-button";
import { i18n } from "discourse-i18n";
import {
  findNodeType,
  propertyDescription,
  propertyLabel,
} from "../../../lib/workflows/property-engine";
import Field from "./field";

export default class AssignmentCollection extends Component {
  @tracked
  itemCount = (this.args.formApi?.get(this.assignmentsPath) || []).length;

  get assignmentsPath() {
    return `${this.args.fieldName}.assignments`;
  }

  get nodeDefinition() {
    return (
      this.args.nodeDefinition ||
      findNodeType(this.args.nodeTypes, this.args.nodeType)
    );
  }

  get label() {
    return propertyLabel(this.nodeDefinition, this.args.fieldName);
  }

  get description() {
    return propertyDescription(this.nodeDefinition, this.args.fieldName);
  }

  get type_options() {
    return this.args.schema.type_options || {};
  }

  get assignment_types() {
    return (
      this.type_options.assignment_types || [
        "string",
        "number",
        "boolean",
        "array",
        "object",
      ]
    );
  }

  get nameSchema() {
    return {
      type: "string",
      required: true,
      ui: { expression: false },
    };
  }

  get typeSchema() {
    return {
      type: "options",
      required: true,
      default: "string",
      options: this.assignment_types,
      ui: { expression: false },
    };
  }

  get showEmptyState() {
    return this.itemCount === 0;
  }

  @action
  emptyAssignment() {
    return {
      id: crypto.randomUUID(),
      name: "",
      value: "",
      type: "string",
    };
  }

  @action
  addAssignment() {
    this.args.form.addItemToCollection(
      this.assignmentsPath,
      this.emptyAssignment()
    );
    this.itemCount++;
  }

  @action
  removeAssignment(removeFn, index) {
    removeFn(index);
    this.itemCount--;
  }

  @action
  clearAssignments() {
    this.args.formApi.set(this.assignmentsPath, []);
    this.itemCount = 0;
  }

  @action
  valueSchema(item) {
    switch (item?.type) {
      case "number":
        return { type: "number" };
      case "boolean":
        return { type: "boolean" };
      case "array":
      case "object":
        return {
          type: "string",
          ui: {
            control: "code",
          },
          control_options: {
            height: 120,
            lang: "json",
          },
        };
      default:
        return { type: "string" };
    }
  }

  <template>
    <@form.Section @title={{this.label}} @subtitle={{this.description}}>
      <@form.Collection
        @name={{this.assignmentsPath}}
        @tagName="div"
        as |collection index item|
      >
        <div class="workflows-property-engine__collection-row">
          <div class="workflows-property-engine__collection-delete">
            <DButton
              @action={{fn this.removeAssignment collection.remove index}}
              @icon="trash-can"
              class="btn-transparent btn-small btn-danger"
            />
          </div>

          <collection.Object
            class="workflows-property-engine__collection-fields"
            as |object|
          >
            <Field
              @form={{object}}
              @formApi={{@formApi}}
              @fieldName="name"
              @label={{i18n
                "discourse_workflows.property_engine.assignment_name"
              }}
              @nodeDefinition={{this.nodeDefinition}}
              @nodeType={{@nodeType}}
              @nodeTypes={{@nodeTypes}}
              @schema={{this.nameSchema}}
            />

            <Field
              @form={{object}}
              @formApi={{@formApi}}
              @fieldName="type"
              @label={{i18n
                "discourse_workflows.property_engine.assignment_type"
              }}
              @nodeDefinition={{this.nodeDefinition}}
              @nodeType={{@nodeType}}
              @nodeTypes={{@nodeTypes}}
              @schema={{this.typeSchema}}
            />

            <Field
              @form={{object}}
              @formApi={{@formApi}}
              @fieldName="value"
              @label={{i18n
                "discourse_workflows.property_engine.assignment_value"
              }}
              @nodeDefinition={{this.nodeDefinition}}
              @nodeType={{@nodeType}}
              @nodeTypes={{@nodeTypes}}
              @schema={{this.valueSchema item}}
            />
          </collection.Object>
        </div>
      </@form.Collection>

      <div class="workflows-property-engine__block-actions">
        <DButton
          @action={{this.addAssignment}}
          @icon="plus"
          @translatedLabel={{i18n
            "discourse_workflows.property_engine.add_field"
          }}
          class="btn-default"
        />

        {{#unless this.showEmptyState}}
          <DButton
            @action={{this.clearAssignments}}
            @icon="xmark"
            @translatedLabel={{i18n
              "discourse_workflows.property_engine.clear_fields"
            }}
            class="btn-flat"
          />
        {{/unless}}
      </div>
    </@form.Section>
  </template>
}
