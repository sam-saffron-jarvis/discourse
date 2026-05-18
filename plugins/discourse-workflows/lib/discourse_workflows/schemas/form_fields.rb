# frozen_string_literal: true

module DiscourseWorkflows
  module Schemas
    module FormFields
      MAX_FIELD_VALUE_LENGTH = 10_000

      ValidationResult =
        Struct.new(:errors, :data, keyword_init: true) do
          def valid?
            errors.empty?
          end
        end

      ValidationError = Struct.new(:field_label, :code, keyword_init: true)

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

      module_function

      def field_key(field)
        field["field_name"].presence || field["field_label"].to_s.parameterize(separator: "_")
      end

      def with_keys(fields)
        Array.wrap(fields).map { |field| field.merge("key" => field_key(field)) }
      end

      def validate_submission(fields, submitted_params)
        submitted = (submitted_params || {}).with_indifferent_access
        errors = []
        data = {}

        with_keys(fields).each do |field|
          key = field["key"]
          value = submitted[key]

          if missing?(field, value)
            errors << build_error(field, :missing)
            next
          end

          begin
            data[key] = coerce(value, field["field_type"])
          rescue ArgumentError, TypeError
            errors << build_error(field, :invalid_value)
          end
        end

        ValidationResult.new(errors: errors, data: data)
      end

      def missing?(field, value)
        return false unless field["required"]
        return false if field["field_type"] == "checkbox"

        value.blank?
      end

      def coerce(value, field_type)
        case field_type
        when "number"
          return if value.blank?

          value.to_s.include?(".") ? Float(value) : Integer(value)
        when "checkbox"
          ActiveModel::Type::Boolean.new.cast(value)
        else
          value.is_a?(String) ? value.truncate(MAX_FIELD_VALUE_LENGTH) : value
        end
      end

      def build_error(field, code)
        ValidationError.new(field_label: field["field_label"], code: code)
      end
    end
  end
end
