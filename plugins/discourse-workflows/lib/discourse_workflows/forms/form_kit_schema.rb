# frozen_string_literal: true

module DiscourseWorkflows
  module Forms
    module FormKitSchema
      module_function

      def build(fields)
        form_fields = DiscourseWorkflows::Schemas::FormFields.with_keys(fields)

        {
          data: initial_data(form_fields),
          fields: form_fields.map { |field| field_schema(field) }.compact,
        }
      end

      def initial_data(fields)
        fields.each_with_object({}) do |field, data|
          next if field["field_type"] == "html"

          data[field["key"]] = initial_value(field)
        end
      end

      def initial_value(field)
        default_value = field["default_value"]

        case field["field_type"]
        when "checkbox"
          ActiveModel::Type::Boolean.new.cast(default_value)
        else
          default_value.presence || ""
        end
      end

      def field_schema(field)
        type = field["field_type"].presence || "text"

        schema = {
          name: field["key"],
          title: field["field_label"],
          description: field["description"],
          type: form_kit_type(type),
          validation: validation_for(field),
          placeholder: field["placeholder"],
          autofocus: false,
        }.compact

        case type
        when "dropdown"
          schema[:options] = options_for(field)
        end

        schema
      end

      def form_kit_type(field_type)
        case field_type
        when "textarea"
          "textarea"
        when "checkbox"
          "checkbox"
        when "dropdown"
          "select"
        when "number"
          "input-number"
        else
          "input"
        end
      end

      def validation_for(field)
        "required" if field["required"] && field["field_type"] != "checkbox"
      end

      def options_for(field)
        options = field["options"]
        values = options.is_a?(Hash) ? options["values"] : options

        Array
          .wrap(values)
          .filter_map do |option|
            value = option.is_a?(Hash) ? option["value"] || option[:value] : option
            next if value.blank?

            { value: value, label: value }
          end
      end
    end
  end
end
