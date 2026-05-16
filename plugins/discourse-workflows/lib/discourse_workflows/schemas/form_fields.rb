# frozen_string_literal: true

module DiscourseWorkflows
  module Schemas
    module FormFields
      ITEM_SCHEMA = {
        field_label: {
          type: :string,
          required: true,
        },
        field_type: {
          type: :options,
          required: true,
          default: "text",
          options: %w[text textarea number checkbox dropdown],
          ui: {
            expression: true,
          },
        },
      }.freeze

      EXTRA_ITEM_SCHEMA = {
        field_name: {
          type: :string,
        },
        required: {
          type: :boolean,
          default: false,
        },
        description: {
          type: :string,
        },
        placeholder: {
          type: :string,
        },
        default_value: {
          type: :string,
        },
        options: {
          type: :fixed_collection,
          visible_if: {
            field_type: %w[dropdown],
          },
          type_options: {
            multiple_values: true,
          },
          options: [
            {
              name: "values",
              values: {
                value: {
                  type: :string,
                  required: true,
                  ui: {
                    show_label: false,
                  },
                },
              },
            },
          ],
        },
      }.freeze

      SCHEMA = {
        type: :fixed_collection,
        required: true,
        type_options: {
          multiple_values: true,
          hide_optional_fields: true,
        },
        options: [{ name: "values", values: ITEM_SCHEMA.merge(EXTRA_ITEM_SCHEMA) }],
      }.freeze

      FORM_OUTPUT_SCHEMA = { submittedAt: :string, formMode: :string }.freeze
      FORM_TRIGGER_OUTPUT_SCHEMA = FORM_OUTPUT_SCHEMA.merge(formQueryParameters: :object).freeze
      OUTPUT_SCHEMA = FORM_OUTPUT_SCHEMA
    end
  end
end
