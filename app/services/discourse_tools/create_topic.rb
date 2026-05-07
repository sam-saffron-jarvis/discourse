# frozen_string_literal: true

module DiscourseTools
  class CreateTopic
    include Service::Base

    params do
      attribute :title, :string
      attribute :raw, :string
      attribute :category_id, :integer
      validates :title, presence: true
      validates :raw, presence: true
    end

    options do
      attribute :tags, :array, default: []
      attribute :skip_validations, :boolean, default: false
      attribute :skip_workflows, :boolean, default: false
    end

    model :category, optional: true
    policy :can_create
    step :create_post

    private

    def fetch_category(params:)
      Category.find_by(id: params.category_id) if params.category_id.present?
    end

    def can_create(guardian:, category:)
      guardian.can_create?(Topic, category)
    end

    def create_post(guardian:, params:, options:, category:)
      args = {
        title: params.title,
        raw: params.raw,
        guardian: guardian,
        skip_validations: options.skip_validations,
      }
      args[:category] = category.id if category
      args[:tags] = options.tags if options.tags.present?
      args[:skip_workflows] = true if options.skip_workflows

      post_creator = PostCreator.new(guardian.user, **args)
      context[:post] = post_creator.create

      fail!(post_creator.errors.full_messages.join(", ")) if post_creator.errors.present?
    end
  end
end
