import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { LinkTo } from "@ember/routing";
import { service } from "@ember/service";
import DButton from "discourse/components/d-button";
import avatar from "discourse/helpers/avatar";
import icon from "discourse/helpers/d-icon";
import formatDate from "discourse/helpers/format-date";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { eq } from "discourse/truth-helpers";
import { i18n } from "discourse-i18n";
import AdminTable from "./admin-table";
import EmptyState from "./empty-state";
import Stats from "./stats";

export default class WorkflowsIndex extends Component {
  @service currentUser;
  @service router;

  @tracked loading = false;

  @action
  async loadMore() {
    if (!this.args.workflows.canLoadMore || this.loading) {
      return;
    }

    this.loading = true;
    try {
      await this.args.workflows.loadMore();
    } finally {
      this.loading = false;
    }
  }

  @action
  async createWorkflow() {
    try {
      const result = await ajax(
        "/admin/plugins/discourse-workflows/workflows.json",
        {
          type: "POST",
          data: {
            workflow: {
              name: i18n("discourse_workflows.default_workflow_name"),
            },
          },
        }
      );
      this.router.transitionTo(
        "adminPlugins.show.discourse-workflows.show",
        result.workflow.id
      );
    } catch (e) {
      popupAjaxError(e);
    }
  }

  @action
  navigateToWorkflow(workflow) {
    this.router.transitionTo(
      "adminPlugins.show.discourse-workflows.show",
      workflow.id
    );
  }

  <template>
    <Stats @stats={{@stats}} />

    <AdminTable
      @items={{@workflows.content}}
      @isLoading={{false}}
      @canLoadMore={{@workflows.canLoadMore}}
      @loadMore={{this.loadMore}}
      @loadingMore={{this.loading}}
      @rowClass="workflows-index__row"
      @onRowClick={{this.navigateToWorkflow}}
    >
      <:empty>
        <EmptyState
          @emoji="wave"
          @title={{i18n
            "discourse_workflows.empty_title"
            username=this.currentUser.displayName
          }}
          @description={{i18n "discourse_workflows.empty_description"}}
          @buttonLabel="discourse_workflows.create_first_workflow"
          @onAction={{this.createWorkflow}}
        />
      </:empty>
      <:toolbar>
        <DButton
          @action={{this.createWorkflow}}
          @label="discourse_workflows.new_workflow"
          @icon="plus"
          class="btn-primary btn-small"
        />
      </:toolbar>
      <:head>
        <th class="d-table__header-cell">{{i18n
            "discourse_workflows.workflow_name"
          }}</th>
        <th class="d-table__header-cell">{{i18n
            "discourse_workflows.last_editor"
          }}</th>
        <th class="d-table__header-cell">{{i18n
            "discourse_workflows.last_update"
          }}</th>
        <th class="d-table__header-cell">{{i18n
            "discourse_workflows.last_run"
          }}</th>
        <th class="d-table__header-cell"></th>
      </:head>
      <:row as |workflow|>
        <td class="d-table__cell --overview workflows-index__name">
          <LinkTo
            @route="adminPlugins.show.discourse-workflows.show"
            @model={{workflow.id}}
            class="d-table__overview-link"
          >
            <strong class="d-table__overview-name">{{workflow.name}}</strong>
            {{#if (eq workflow.last_execution_status "error")}}
              <span
                class="workflows-index__warning"
                role="img"
                aria-label={{i18n "discourse_workflows.last_execution_failed"}}
                title={{i18n "discourse_workflows.last_execution_failed"}}
              >
                {{icon "triangle-exclamation"}}
              </span>
            {{/if}}
          </LinkTo>
        </td>
        <td class="d-table__cell --detail workflows-index__last-editor">
          <div class="d-table__mobile-label">
            {{i18n "discourse_workflows.last_editor"}}
          </div>
          {{#if workflow.updated_by}}
            <a
              href={{workflow.updated_by.path}}
              class="workflows-index__last-editor-link"
            >
              {{avatar workflow.updated_by imageSize="tiny"}}
              <span>{{workflow.updated_by.username}}</span>
            </a>
          {{/if}}
        </td>
        <td class="d-table__cell --detail workflows-index__last-update">
          <div class="d-table__mobile-label">
            {{i18n "discourse_workflows.last_update"}}
          </div>
          {{formatDate workflow.updated_at format="medium"}}
        </td>
        <td class="d-table__cell --detail workflows-index__last-run">
          <div class="d-table__mobile-label">
            {{i18n "discourse_workflows.last_run"}}
          </div>
          {{#if workflow.last_execution_at}}
            {{formatDate workflow.last_execution_at format="medium"}}
          {{else}}
            {{i18n "discourse_workflows.last_execution_never"}}
          {{/if}}
        </td>
        <td class="d-table__cell --detail workflows-index__status">
          {{#if workflow.published_version_id}}
            <span class="workflows-index__badge is-published">
              {{i18n "discourse_workflows.published"}}
            </span>
          {{else}}
            <span class="workflows-index__badge is-unpublished">
              {{i18n "discourse_workflows.unpublished"}}
            </span>
          {{/if}}
        </td>
      </:row>
    </AdminTable>
  </template>
}
