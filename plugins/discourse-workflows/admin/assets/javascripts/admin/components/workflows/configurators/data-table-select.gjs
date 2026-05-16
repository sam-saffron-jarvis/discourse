import { hash } from "@ember/helper";
import { action } from "@ember/object";
import { service } from "@ember/service";
import DButton from "discourse/components/d-button";
import ComboBox from "discourse/select-kit/components/combo-box";
import ComboBoxField from "./combo-box";
import ExpressionWrapper from "./expression-wrapper";

export default class DataTableSelect extends ComboBoxField {
  @service router;

  @action
  manageDataTables() {
    this.router.transitionTo(
      "adminPlugins.show.discourse-workflows-data-tables"
    );
  }

  <template>
    <ExpressionWrapper
      @field={{@field}}
      @supportsExpression={{@supportsExpression}}
      @placeholder={{@placeholder}}
    >
      <div class="workflows-property-engine__select-with-action">
        <ComboBox
          @content={{this.options}}
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
        {{#unless @field.value}}
          <DButton
            @action={{this.manageDataTables}}
            @label="discourse_workflows.data_tables.manage_data_tables"
            @icon="plus"
            class="btn-default"
          />
        {{/unless}}
      </div>
    </ExpressionWrapper>
  </template>
}
