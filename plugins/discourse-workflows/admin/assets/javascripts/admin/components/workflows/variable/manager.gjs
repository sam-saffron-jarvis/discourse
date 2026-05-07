import { concat, fn } from "@ember/helper";
import { action } from "@ember/object";
import { service } from "@ember/service";
import DButton from "discourse/components/d-button";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { clipboardCopy } from "discourse/lib/utilities";
import { i18n } from "discourse-i18n";
import AdminTable from "../admin-table";
import CrudManager from "../crud-manager";
import EmptyState from "../empty-state";
import VariableModal from "./modal";

export default class VariablesManager extends CrudManager {
  @service workflowsNodeTypes;

  get itemsKey() {
    return "variables";
  }

  get basePath() {
    return "/admin/plugins/discourse-workflows/variables";
  }

  @action
  addVariable() {
    this.modal.show(VariableModal, {
      model: {
        variable: null,
        onSave: async (data) => {
          await ajax(this.apiUrl, {
            type: "POST",
            data,
          });
          this.workflowsNodeTypes.invalidateWorkflowVars();
          await this.loadItems();
        },
      },
    });
  }

  @action
  editVariable(variable) {
    this.modal.show(VariableModal, {
      model: {
        variable,
        onSave: async (data) => {
          await ajax(`${this.basePath}/${variable.id}.json`, {
            type: "PUT",
            data,
          });
          this.workflowsNodeTypes.invalidateWorkflowVars();
          await this.loadItems();
        },
      },
    });
  }

  @action
  deleteVariable(variable) {
    this.dialog.deleteConfirm({
      message: i18n("discourse_workflows.variables.delete_confirm", {
        key: variable.key,
      }),
      didConfirm: async () => {
        try {
          await ajax(`${this.basePath}/${variable.id}.json`, {
            type: "DELETE",
          });
          this.workflowsNodeTypes.invalidateWorkflowVars();
          await this.loadItems();
        } catch (e) {
          popupAjaxError(e);
        }
      },
    });
  }

  @action
  async copySyntax(key) {
    await clipboardCopy(`$vars.${key}`);
  }

  <template>
    <AdminTable
      @items={{this.items}}
      @isLoading={{this.isLoading}}
      @canLoadMore={{this.canLoadMore}}
      @loadMore={{this.loadMore}}
      @loadingMore={{this.loadingMore}}
      @onRowClick={{this.editVariable}}
    >
      <:empty>
        <EmptyState
          @emoji="wave"
          @title={{i18n
            "discourse_workflows.variables.empty_title"
            username=this.currentUser.displayName
          }}
          @description={{i18n
            "discourse_workflows.variables.empty_description"
          }}
          @buttonLabel="discourse_workflows.variables.add_first"
          @onAction={{this.addVariable}}
        />
      </:empty>
      <:toolbar>
        <DButton
          @action={{this.addVariable}}
          @label="discourse_workflows.variables.add"
          @icon="plus"
          class="btn-primary btn-small"
        />
      </:toolbar>
      <:head>
        <th class="d-table__header-cell">{{i18n
            "discourse_workflows.variables.key"
          }}</th>
        <th class="d-table__header-cell">{{i18n
            "discourse_workflows.variables.value"
          }}</th>
        <th class="d-table__header-cell">{{i18n
            "discourse_workflows.variables.usage_syntax"
          }}</th>
        <th class="d-table__header-cell"></th>
      </:head>
      <:row as |variable|>
        <td class="d-table__cell --overview">
          <strong class="d-table__overview-name">{{variable.key}}</strong>
        </td>
        <td class="d-table__cell --detail">
          <div class="d-table__mobile-label">
            {{i18n "discourse_workflows.variables.value"}}
          </div>
          {{variable.value}}
        </td>
        <td class="d-table__cell --detail">
          <div class="d-table__mobile-label">
            {{i18n "discourse_workflows.variables.usage_syntax"}}
          </div>
          <DButton
            @action={{fn this.copySyntax variable.key}}
            @translatedLabel={{concat "$vars." variable.key}}
            @icon="copy"
            @title="discourse_workflows.variables.copy_syntax"
            class="btn-flat btn-small"
          />
        </td>
        <td class="d-table__cell --controls">
          <div class="d-table__cell-actions">
            <DButton
              @action={{fn this.deleteVariable variable}}
              @icon="trash-can"
              class="btn-flat btn-small btn-danger"
            />
          </div>
        </td>
      </:row>
    </AdminTable>
  </template>
}
