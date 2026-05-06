import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { concat, fn } from "@ember/helper";
import { action } from "@ember/object";
import { service } from "@ember/service";
import DButton from "discourse/components/d-button";
import icon from "discourse/helpers/d-icon";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { i18n } from "discourse-i18n";
import AdminTable from "../admin-table";
import EmptyState from "../empty-state";

const STATUS_ICONS = {
  success: "circle-check",
  error: "circle-xmark",
  running: "spinner",
  waiting: "clock",
};

function statusIcon(status) {
  return STATUS_ICONS[status] || "circle";
}

function formatTime(timestamp) {
  if (!timestamp) {
    return "—";
  }
  return new Date(timestamp).toLocaleString();
}

function runTime(execution) {
  const ms = execution.run_time_ms;
  if (ms == null) {
    return "—";
  }
  return ms < 1000 ? `${ms}ms` : `${(ms / 1000).toFixed(1)}s`;
}

export default class ExecutionsManager extends Component {
  @service currentUser;
  @service dialog;
  @service router;

  @tracked executions = null;
  @tracked loadMoreUrl = null;
  @tracked loadingMore = false;

  constructor() {
    super(...arguments);
    this.loadExecutions();
  }

  async loadExecutions() {
    try {
      const url = this.args.workflowId
        ? `/admin/plugins/discourse-workflows/workflows/${this.args.workflowId}/executions.json`
        : "/admin/plugins/discourse-workflows/executions.json";
      const result = await ajax(url);
      this.executions = result.executions;
      this.loadMoreUrl = result.meta?.load_more_executions;
    } catch (e) {
      popupAjaxError(e);
    }
  }

  get canLoadMore() {
    return !!this.loadMoreUrl;
  }

  @action
  async loadMore() {
    if (!this.loadMoreUrl || !this.canLoadMore || this.loadingMore) {
      return;
    }

    this.loadingMore = true;
    try {
      const result = await ajax(this.loadMoreUrl);
      this.executions = [...this.executions, ...result.executions];
      this.loadMoreUrl = result.meta?.load_more_executions;
    } catch (e) {
      popupAjaxError(e);
    } finally {
      this.loadingMore = false;
    }
  }

  get isLoading() {
    return this.executions === null;
  }

  @action
  async deleteSelected(selectedIds, clearSelection) {
    const count = selectedIds.size;
    this.dialog.yesNoConfirm({
      message: i18n("discourse_workflows.executions.delete_confirm", { count }),
      didConfirm: async () => {
        try {
          await ajax("/admin/plugins/discourse-workflows/executions.json", {
            type: "DELETE",
            data: { ids: [...selectedIds] },
          });
          clearSelection();
          await this.loadExecutions();
        } catch (e) {
          popupAjaxError(e);
        }
      },
    });
  }

  @action
  navigateToExecution(execution) {
    this.router.transitionTo(
      "adminPlugins.show.discourse-workflows.show.executions.show",
      execution.workflow_id,
      execution.id
    );
  }

  <template>
    <AdminTable
      @items={{this.executions}}
      @isLoading={{this.isLoading}}
      @canLoadMore={{this.canLoadMore}}
      @loadMore={{this.loadMore}}
      @loadingMore={{this.loadingMore}}
      @selectable={{true}}
      @onRowClick={{this.navigateToExecution}}
    >
      <:empty>
        <EmptyState
          @emoji="👋"
          @title={{i18n
            "discourse_workflows.executions.empty_title"
            username=this.currentUser.username
          }}
          @description={{i18n
            "discourse_workflows.executions.empty_description"
          }}
        />
      </:empty>
      <:toolbar as |toolbar|>
        {{#if toolbar.hasSelection}}
          <DButton
            @action={{fn
              this.deleteSelected
              toolbar.selectedIds
              toolbar.clearSelection
            }}
            @label="discourse_workflows.executions.delete_selected"
            @icon="trash-can"
            class="btn-danger btn-small"
          />
          <DButton
            @action={{toolbar.clearSelection}}
            @icon="xmark"
            @label="discourse_workflows.executions.clear_selection"
            class="btn-default btn-small"
          />
        {{/if}}
      </:toolbar>
      <:head>
        {{#unless @workflowId}}
          <th>{{i18n "discourse_workflows.executions.workflow"}}</th>
        {{/unless}}
        <th>{{i18n "discourse_workflows.executions.status"}}</th>
        <th>{{i18n "discourse_workflows.executions.started_at"}}</th>
        <th>{{i18n "discourse_workflows.executions.run_time"}}</th>
      </:head>
      <:row as |execution|>
        {{#unless @workflowId}}
          <td>{{execution.workflow_name}}</td>
        {{/unless}}
        <td>
          <span
            class="workflows-executions-manager__status --{{execution.status}}"
          >
            {{icon (statusIcon execution.status)}}
            {{i18n
              (concat
                "discourse_workflows.executions.statuses." execution.status
              )
            }}
          </span>
        </td>
        <td>{{formatTime execution.started_at}}</td>
        <td>{{runTime execution}}</td>
      </:row>
    </AdminTable>
  </template>
}
