# frozen_string_literal: true

module DiscourseWorkflows
  module Nodes
    module Code
      class V1 < NodeType
        DEFAULT_CODE = <<~JS
          // Available variables:
          //   $input.item.json       - current item's JSON data
          //   $input.all()           - array of all input items
          //   $json                  - shortcut for $input.item.json
          //   $("NodeName").item     - access the paired item from another node
          //   $vars.KEY              - workflow variables
          //   $site_settings.NAME    - site settings
          //   $execution             - execution metadata (id, workflow_name, ...)
          //   $current_user          - user running the workflow
          //   console.log/warn/error - logging

          // Example: add a new field called 'foo' to every input item
          var items = $input.all();
          items.forEach(function(item) {
            item.json.foo = 1;
          });

          return items;
        JS
        N8N_ITEM_KEYS = %w[json binary pairedItem error index].freeze

        description(
          name: "action:code",
          version: "1.0",
          defaults: {
            icon: "code",
            color: "red",
          },
          properties: {
            mode: {
              type: :options,
              default: "run_once_for_all_items",
              options: %w[run_once_for_each_item run_once_for_all_items],
              ui: {
                expression: false,
              },
            },
            code: {
              type: :string,
              required: true,
              default: DEFAULT_CODE,
              ui: {
                control: :code,
                expression: false,
              },
              control_options: {
                height: 300,
                lang: :javascript,
              },
            },
            output_fields: {
              type: :array,
              required: false,
              ui: {
                hidden: true,
              },
            },
          },
        )

        def execute(exec_ctx)
          code = @configuration["code"].to_s
          mode = @configuration["mode"] || "run_once_for_all_items"
          validate_no_disallowed_methods_in_run_for_each!(code) if mode == "run_once_for_each_item"

          items =
            exec_ctx.with_sandbox(capture_logs: true) do |sandbox|
              setup_code_sandbox!(
                sandbox,
                exec_ctx.input_items,
                @configuration,
                DiscourseWorkflows::InputContext.from_node_context(exec_ctx.get_context(:node)),
                mode,
              )
              if mode == "run_once_for_all_items"
                execute_all_items(sandbox, code)
              else
                execute_per_item(sandbox, code, exec_ctx.input_items)
              end
            end
          [items]
        end

        private

        def execute_per_item(sandbox, code, input_items)
          input_items.each_with_index.filter_map do |item, item_index|
            sandbox.rebind_code_item(item, item_index:)
            result = evaluate_code(sandbox, code)
            next if result["type"] == "null"

            validate_run_code_each_item(result, item_index)
          end
        end

        def execute_all_items(sandbox, code)
          result = evaluate_code(sandbox, code)
          return [] if result["type"] == "null"

          validate_run_code_all_items(result)
        end

        def evaluate_code(sandbox, code)
          sandbox.eval(<<~JS)
            (function() {
              var __discourseWorkflowsCodeResult = (function() { #{code} })();

              if (__discourseWorkflowsCodeResult === null) {
                return { type: "null" };
              }

              if (typeof __discourseWorkflowsCodeResult === "undefined") {
                return { type: "undefined" };
              }

              return {
                type: typeof __discourseWorkflowsCodeResult,
                value: __discourseWorkflowsCodeResult
              };
            })()
          JS
        end

        def validate_run_code_each_item(result, item_index)
          value = result["value"]

          if result["type"] != "object"
            raise_validation_error!(
              "Code doesn't return an object",
              "Please return an object representing the output item. " \
                "('#{value}' was returned instead.)",
              item_index:,
            )
          end

          if value.is_a?(Array)
            first_sentence =
              (
                if value.length > 0
                  "An array of #{value.first.class.name.downcase}s was returned."
                else
                  "An empty array was returned."
                end
              )
            raise_validation_error!(
              "Code doesn't return a single object",
              "#{first_sentence} If you need to output multiple items, please use the " \
                "'Run Once for All Items' mode instead.",
              item_index:,
            )
          end

          unless value.is_a?(Hash)
            raise_validation_error!(
              "Code doesn't return an object",
              "Please return an object representing the output item.",
              item_index:,
            )
          end

          return_data = normalize_items([value]).first
          validate_item!(return_data, item_index:)
          validate_top_level_keys!(return_data, item_index:)
          return_data["pairedItem"] ||= { "item" => item_index }
          normalize_item_result(return_data)
        end

        def validate_run_code_all_items(result)
          value = result["value"]

          if result["type"] != "object"
            raise_validation_error!(
              "Code doesn't return items properly",
              "Please return an array of objects, one for each item you would like to output.",
            )
          end

          if value.is_a?(Array)
            items = value.map { |item| stringify_result(item) }
            unless items.all? { |item| item.is_a?(Hash) }
              raise_validation_error!(
                "Code doesn't return items properly",
                "Please return an array of objects, one for each item you would like to output.",
              )
            end

            if items.any? { |item| item.keys.any? { |key| n8n_item_key?(key) } }
              items.each_with_index do |item, index|
                validate_top_level_keys!(item, item_index: index)
              end
            end
          elsif !value.is_a?(Hash)
            raise_validation_error!(
              "Code doesn't return items properly",
              "Please return an array of objects, one for each item you would like to output.",
            )
          end

          normalize_items(value).tap do |return_data|
            return_data.each_with_index { |item, index| validate_item!(item, item_index: index) }
          end
        end

        def normalize_items(execution_data)
          execution_data = stringify_result(execution_data)

          if execution_data.is_a?(Hash)
            return [normalize_item_result(execution_data)] if execution_data.key?("json")

            return [wrap(execution_data)]
          end

          if execution_data.all? { |item| item.is_a?(Hash) && item.key?("json") }
            return execution_data.map { |item| normalize_item_result(item) }
          end

          if execution_data.any? { |item| item.is_a?(Hash) && item.key?("json") }
            raise_validation_error!(
              "Inconsistent item format",
              "Every returned item must use the same format.",
            )
          end

          if execution_data.all? { |item| item.is_a?(Hash) && item.key?("binary") }
            return(
              execution_data.map do |item|
                normalize_item_result("json" => item.except("binary"), "binary" => item["binary"])
              end
            )
          end

          if execution_data.any? { |item| item.is_a?(Hash) && item.key?("binary") }
            raise_validation_error!(
              "Inconsistent item format",
              "Every returned item must use the same format.",
            )
          end

          execution_data.map { |item| wrap(item) }
        end

        def validate_item!(item, item_index:)
          unless item["json"].is_a?(Hash)
            raise_validation_error!(
              "A 'json' property isn't an object",
              "In the returned data, every key named 'json' must point to an object.",
              item_index:,
            )
          end

          if item.key?("binary") && !item["binary"].is_a?(Hash)
            raise_validation_error!(
              "A 'binary' property isn't an object",
              "In the returned data, every key named 'binary' must point to an object.",
              item_index:,
            )
          end
        end

        def validate_top_level_keys!(item, item_index:)
          found_reserved_key = nil
          unknown_keys = []

          item.each_key do |key|
            if n8n_item_key?(key)
              found_reserved_key ||= key
            else
              unknown_keys << key
            end
          end

          return if unknown_keys.empty?

          if found_reserved_key
            raise_validation_error!(
              "Invalid output format",
              "An output item contains the reserved key #{found_reserved_key}. " \
                "Wrap each item in an object under a key called json.",
              item_index:,
            )
          end

          raise_validation_error!(
            "Unknown top-level item key: #{unknown_keys.first}",
            "Access the properties of an item under .json, e.g. item.json",
            item_index:,
          )
        end

        def validate_no_disallowed_methods_in_run_for_each!(code)
          match = code.match(/\$input\.(?<disallowed_method>first|last|all|itemMatching)/)
          return if match.blank?

          disallowed_method = match[:disallowed_method]
          line_number =
            code
              .split("\n")
              .find_index do |line|
                stripped = line.strip
                line.include?(disallowed_method) && !stripped.start_with?("//", "/*", "*")
              end
          return if line_number.nil?

          raise_validation_error!(
            "Can't use .#{disallowed_method}() here",
            "This is only available in 'Run Once for All Items' mode.",
            item_index: 0,
            line_number: line_number + 1,
          )
        end

        def raise_validation_error!(message, description, item_index: nil, line_number: nil)
          suffix = +""
          suffix << " [line #{line_number}" if line_number
          if item_index
            suffix << (line_number ? ", for item #{item_index}" : " [item #{item_index}")
          end
          (suffix.presence&.<<("]"))

          raise DiscourseWorkflows::NodeError, "#{message}#{suffix}: #{description}"
        end

        def n8n_item_key?(key)
          N8N_ITEM_KEYS.include?(key.to_s)
        end

        def stringify_result(value)
          case value
          when Hash
            value.deep_stringify_keys
          when Array
            value.map { |item| stringify_result(item) }
          else
            value
          end
        end

        def normalize_item_result(result)
          if result.key?("pairedItem")
            result["pairedItem"] = Item.normalize_paired_item(result["pairedItem"])
          end
          result
        end

        def setup_code_sandbox!(sandbox, input_items, input_params, input_context, mode)
          sandbox.declare_json("__allInputItems", input_items)
          sandbox.declare_json("__inputParams", input_params)
          sandbox.declare_json("__inputContext", input_context)
          sandbox.declare_json("__nodeMode", mode)
          sandbox.eval(<<~JS)
            function __WorkflowCodeInput(item) {
              this.item = item;
              this.params = __inputParams;
              this.context = __inputContext;
            }

            __WorkflowCodeInput.prototype.all = function() {
              if (arguments.length) {
                throw new Error("$input.all() should have no arguments");
              }

              return __allInputItems;
            };

            __WorkflowCodeInput.prototype.first = function() {
              if (arguments.length) {
                throw new Error("$input.first() should have no arguments");
              }

              return __allInputItems[0] || { json: {} };
            };

            __WorkflowCodeInput.prototype.last = function() {
              if (arguments.length) {
                throw new Error("$input.last() should have no arguments");
              }

              return __allInputItems[__allInputItems.length - 1] || { json: {} };
            };

            var $input = new __WorkflowCodeInput({ json: {} });
            var __itemIndex = 0;
            Object.defineProperty(this, '$json', {
              get: function() { return $input.item.json; },
              set: function(value) { $input.item.json = value; },
              configurable: true
            });
            Object.defineProperty(this, '$itemIndex', {
              get: function() { return __itemIndex; },
              set: function(value) { __itemIndex = value; },
              configurable: true
            });
            Object.defineProperty(this, '$items', {
              value: function(name) {
                if (typeof name === 'undefined') {
                  return $input.all();
                }

                return $(name).all();
              },
              configurable: true,
              writable: false
            });
            if (__nodeMode === "run_once_for_all_items") {
              Object.defineProperty(this, 'items', {
                value: __allInputItems,
                configurable: true,
                writable: false
              });
            } else {
              Object.defineProperty(this, 'item', {
                get: function() { return $input.item; },
                configurable: true
              });
            }
          JS
        end
      end
    end
  end
end
