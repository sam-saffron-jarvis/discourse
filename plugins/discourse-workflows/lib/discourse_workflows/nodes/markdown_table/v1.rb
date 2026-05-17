# frozen_string_literal: true

module DiscourseWorkflows
  module Nodes
    module MarkdownTable
      class V1 < NodeType
        MAPPING_MODES = %w[manual auto].freeze

        description(
          name: "action:markdown_table",
          version: "1.0",
          defaults: {
            icon: "table-cells",
            color: "green",
          },
          group: "data",
          properties: {
            mapping_mode: {
              type: :options,
              required: true,
              options: MAPPING_MODES,
              default: "manual",
              ui: {
                expression: false,
              },
            },
            columns: {
              type: :fixed_collection,
              required: false,
              visible_if: {
                mapping_mode: "manual",
              },
              type_options: {
                multiple_values: true,
              },
              options: [
                {
                  name: "values",
                  values: {
                    header: {
                      type: :string,
                      required: true,
                      ui: {
                        expression: false,
                      },
                    },
                    value: {
                      type: :string,
                      required: true,
                    },
                  },
                },
              ],
            },
          },
          output_schema: {
            "markdown" => :string,
          },
        )

        def execute(exec_ctx)
          headers, rows =
            if @configuration["mapping_mode"] == "auto"
              auto_table(exec_ctx.input_items)
            else
              configured_table(exec_ctx, CollectionParameters.rows(@configuration, "columns"))
            end

          return [[wrap({ "markdown" => "" })]] if headers.empty?

          [[wrap({ "markdown" => render_table(headers, rows) })]]
        end

        private

        def auto_table(input_items)
          headers = input_items.flat_map { |item| (item["json"] || {}).keys }.uniq
          rows =
            input_items.map do |item|
              json = item["json"] || {}
              headers.map { |key| format_cell(json[key]) }
            end
          [headers, rows]
        end

        def configured_table(exec_ctx, columns)
          headers = columns.map { |c| c["header"].to_s }
          rows =
            exec_ctx.input_items.map do |item|
              resolved = CollectionParameters.rows(exec_ctx.get_parameters(item), "columns")
              resolved.map { |c| format_cell(c["value"]) }
            end
          [headers, rows]
        end

        def render_table(headers, rows)
          ([headers, headers.map { "---" }] + rows).map { |cells| row_line(cells) }.join("\n")
        end

        def row_line(cells)
          "| #{cells.join(" | ")} |"
        end

        def format_cell(value)
          raw =
            if value.nil?
              ""
            elsif value.is_a?(Hash) || value.is_a?(Array)
              JSON.generate(value)
            else
              value.to_s
            end

          sanitize_cell(raw)
        end

        def sanitize_cell(str)
          str.gsub("|", "\\|").gsub(/\r\n|\n/, "<br>")
        end
      end
    end
  end
end
