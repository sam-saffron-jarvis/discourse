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
        RUN_ONCE_FOR_ALL_ITEMS = "runOnceForAllItems"
        RUN_ONCE_FOR_EACH_ITEM = "runOnceForEachItem"

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
              default: RUN_ONCE_FOR_ALL_ITEMS,
              options: [RUN_ONCE_FOR_EACH_ITEM, RUN_ONCE_FOR_ALL_ITEMS],
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
          mode = @configuration["mode"] || RUN_ONCE_FOR_ALL_ITEMS
          validate_mode!(mode)
          validate_no_disallowed_methods_in_run_for_each!(code) if mode == RUN_ONCE_FOR_EACH_ITEM
          result_validator = result_validator(exec_ctx)

          items =
            exec_ctx.with_sandbox(capture_logs: true) do |sandbox|
              setup_code_sandbox!(
                sandbox,
                exec_ctx.input_items,
                @configuration,
                exec_ctx.input_context,
              )
              if mode == RUN_ONCE_FOR_ALL_ITEMS
                execute_all_items(sandbox, code, result_validator)
              else
                execute_per_item(sandbox, code, exec_ctx.input_items, result_validator)
              end
            end
          [items]
        end

        private

        def execute_per_item(sandbox, code, input_items, result_validator)
          input_items.each_with_index.filter_map do |item, item_index|
            sandbox.rebind_code_item(item, item_index:)
            result = evaluate_code(sandbox, code)
            next if result["type"] == "null"

            result_validator.validate_each_item(result, item_index:)
          end
        end

        def execute_all_items(sandbox, code, result_validator)
          result = evaluate_code(sandbox, code)
          return [] if result["type"] == "null"

          result_validator.validate_all_items(result)
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

          raise_node_error!(
            "Can't use .#{disallowed_method}() here",
            description: "This is only available in 'Run Once for All Items' mode.",
            item_index: 0,
            line_number: line_number + 1,
          )
        end

        def validate_mode!(mode)
          return if [RUN_ONCE_FOR_ALL_ITEMS, RUN_ONCE_FOR_EACH_ITEM].include?(mode)

          raise_node_error!(
            "Invalid Code mode",
            description: "#{mode.inspect} is not a supported Code execution mode.",
          )
        end

        def result_validator(exec_ctx)
          ResultValidator.new(
            normalize_items: ->(value) { exec_ctx.normalize_items(value) },
            raise_error:
              lambda do |message, description:, item_index: nil, line_number: nil|
                raise_node_error!(message, description:, item_index:, line_number:)
              end,
          )
        end

        def setup_code_sandbox!(sandbox, input_items, input_params, input_context)
          sandbox.declare_json("__allInputItems", input_items)
          sandbox.declare_json("__inputParams", input_params)
          sandbox.declare_json("__inputContext", input_context)
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
          JS
        end
      end
    end
  end
end
