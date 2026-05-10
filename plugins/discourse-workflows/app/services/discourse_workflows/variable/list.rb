# frozen_string_literal: true

module DiscourseWorkflows
  class Variable::List
    include Service::Base

    policy :can_manage_workflows, class_name: Policy::CanManageWorkflows

    params do
      attribute :cursor, :integer
      attribute :limit, :integer

      after_validation do
        self.limit =
          (limit || DiscourseWorkflows::Pagination::DEFAULT_LIMIT).clamp(
            1,
            DiscourseWorkflows::Pagination::MAX_LIMIT,
          )
      end
    end

    model :variables, optional: true
    model :has_more, :compute_has_more, optional: true
    model :total_rows, :count_total_rows

    only_if(:has_more) { model :load_more_url, :build_load_more_url, optional: true }

    private

    def fetch_variables(params:)
      scope = DiscourseWorkflows::Variable.includes(:created_by).order(id: :desc)
      scope = scope.where("id < ?", params.cursor) if params.cursor
      scope.limit(params.limit + 1).to_a
    end

    def compute_has_more(params:, variables:)
      has_more = variables.size > params.limit
      variables.pop if has_more
      has_more
    end

    def has_more
      context[:has_more]
    end

    def count_total_rows
      DiscourseWorkflows::Variable.count
    end

    def build_load_more_url(params:, variables:)
      "/admin/plugins/discourse-workflows/variables.json?cursor=#{variables.last.id}&limit=#{params.limit}"
    end
  end
end
