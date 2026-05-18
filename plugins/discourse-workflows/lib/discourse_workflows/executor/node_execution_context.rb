# frozen_string_literal: true

module DiscourseWorkflows
  class Executor
    class NodeExecutionContext
      MISSING = Object.new.freeze
      JAVASCRIPT_UNDEFINED =
        Object
          .new
          .tap do |undefined|
            def undefined.to_s
              "undefined"
            end

            def undefined.inspect
              "undefined"
            end
          end
          .freeze
      JobResult = Data.define(:ok, :result, :error)

      attr_reader :user,
                  :vars,
                  :expression_errors,
                  :condition_details,
                  :log,
                  :execution_hints,
                  :execution_id,
                  :resume_token,
                  :node_id,
                  :node_identifier,
                  :waiting_until

      def initialize(
        input_items:,
        input_groups: nil,
        parameters: nil,
        credentials: {},
        settings: {},
        webhook_id: nil,
        property_schema: {},
        credential_schema: [],
        node_context: {},
        user: nil,
        resolver: nil,
        vars: nil,
        workflow: nil,
        execution_id: nil,
        resume_token: nil,
        node_id: nil,
        node_identifier: nil,
        execution_mode: :normal,
        flow_context: nil,
        resolver_context: nil,
        workflow_dependencies: nil
      )
        @input_groups = normalize_input_groups(input_groups, input_items)
        @input_items = @input_groups[0] || []
        split =
          NodeData.split(
            parameters: parameters || {},
            credentials: credentials,
            settings: settings,
            webhook_id: webhook_id,
          )
        @parameters = split["parameters"]
        @credentials = split["credentials"]
        @property_schema = property_schema
        @credential_schema = NodeData.normalize_credential_definitions(credential_schema)
        @node_context = node_context
        @user = user
        @resolver = resolver
        @vars = vars
        @workflow = workflow
        @execution_id = execution_id
        @resume_token = resume_token
        @node_id = node_id
        @node_identifier = node_identifier.presence&.to_s
        @execution_mode = execution_mode
        @flow_context = flow_context || {}
        @resolver_context = resolver_context || {}
        @expression_errors = []
        @condition_details = []
        @log = StepLog.new
        @execution_hints = []
        @waiting = false
        @waiting_until = nil
        @workflow_dependencies = workflow_dependencies
      end

      def get_context(scope = :node)
        case scope
        when :node
          @node_context
        else
          raise ArgumentError, "Unknown context scope: #{scope}. Use :node"
        end
      end

      def input_items(input_key = nil)
        return @input_items if input_key.nil?

        @input_groups.fetch(input_index(input_key)) { [] }
      end

      def inputs
        max_index = @input_groups.keys.max || 0
        Array.new(max_index + 1) { |index| @input_groups[index] || [] }
      end

      def input_context
        InputContext.from_node_context(get_context(:node))
      end

      def get_mode
        @execution_mode.to_s
      end

      def get_input_data(input_index = 0, _connection_type = nil)
        input_items(input_index)
      end

      def continue_on_fail
        false
      end

      def start_job(job_type, settings, item_index)
        raise ArgumentError, "Unsupported job type: #{job_type}" unless job_type == "javascript"

        JobResult.new(
          ok: true,
          result: run_javascript_job(settings.deep_stringify_keys, item_index),
          error: nil,
        )
      rescue => e
        JobResult.new(ok: false, result: nil, error: e)
      end

      def get_node_parameter(path, item = nil, default: nil, ensure_type: nil, options: {})
        path_str = path.to_s
        if raw_expressions?(options)
          raw_value = raw_parameter_path(path_str)
          value = raw_value.equal?(MISSING) ? default : raw_value
          return ensure_parameter_type(value, ensure_type, path_str)
        end

        item ||= input_items.first || { "json" => {} }
        with_item(item) do
          resolved = resolve_parameter_path(path_str)
          value = resolved.equal?(MISSING) ? default : resolved
          ensure_parameter_type(value, ensure_type, path_str)
        end
      end

      def get_node_parameters(item = nil)
        item ||= input_items.first || { "json" => {} }
        with_item(item) { resolve_all_parameters }
      end

      def get_fixed_collection_rows(
        path,
        item,
        group: CollectionParameters::DEFAULT_GROUP,
        default: []
      )
        value = get_node_parameter(path, item, default: MISSING)
        return default if value.equal?(MISSING)

        CollectionParameters.rows_from_value(value, group: group)
      end

      def get_collection_options(path, item, default: {})
        value = get_node_parameter(path, item, default: MISSING)
        return default if value.equal?(MISSING)

        value.is_a?(Hash) ? value : default
      end

      def helpers
        @helpers ||=
          ContextHelpers.new(
            node_identifier: node_identifier,
            data_table_access_validator: ->(data_table_id) do
              ensure_data_table_access!(data_table_id)
            end,
          )
      end

      def credential_reference?(slot)
        declared_credential_slot?(slot) && credential_id_for(slot).present?
      end

      def get_credential(slot)
        raise ArgumentError, "credential slot is required" if slot.blank?

        credential_id = credential_id_for(slot)
        ensure_credential_access!(slot, credential_id)
        credential = DiscourseWorkflows::Credential.find_by(id: credential_id)
        raise Discourse::InvalidAccess if credential.nil?
        unless credential_type_allowed?(slot, credential.credential_type)
          raise Discourse::InvalidAccess
        end

        @resolver.resolve_hash(credential.decrypted_data)
      end

      def find_user(username: nil, id: nil)
        if username.present? == id.present?
          raise ArgumentError, "Provide exactly one of username or id"
        end

        if username.present?
          user = User.find_by(username: username)
          raise DiscourseWorkflows::NodeError, "User '#{username}' not found" if user.nil?
        else
          user = User.find_by(id: id)
          raise DiscourseWorkflows::NodeError, "User with id #{id} not found" if user.nil?
        end

        user
      end

      def http_request(method:, url:, headers: {}, body: nil, options: {})
        HttpClient.new(self).request(method:, url:, headers:, body:, options:)
      end

      def collect_errors!
        @expression_errors = @resolver&.expression_errors || []
      end

      def put_execution_to_wait(waiting_until = nil)
        @waiting = true
        @waiting_until = waiting_until
      end

      def resume_action_id(action)
        DiscourseWorkflows::InteractiveResume.action_id(
          execution_id: execution_id,
          resume_token: resume_token,
          action: action,
        )
      end

      def add_execution_hint(message, location: "outputPane")
        @execution_hints << { "message" => message, "location" => location }
      end

      def waiting?
        @waiting
      end

      def with_item(item)
        @resolver.with_item(item, item_index: item_index_for(item)) { yield }
      end

      def paired_item_for(item, input: 0)
        input_index = input_index(input)
        paired_item = { "item" => item_index_for(item, input_index:) }
        paired_item["input"] = input_index if input_index != 0
        paired_item
      end

      private

      def ensure_data_table_access!(data_table_id)
        if @workflow && @node_id
          return if workflow_references_dependency?("data_table_id", data_table_id)
        elsif @parameters["data_table_id"].to_s == data_table_id
          return
        end

        raise Discourse::InvalidAccess
      end

      def ensure_credential_access!(slot, credential_id)
        raise Discourse::InvalidAccess if credential_id.blank? || !declared_credential_slot?(slot)

        if @workflow && @node_id
          return if workflow_references_dependency?("credential_id", credential_id)
        elsif credential_id_for(slot) == credential_id
          return
        end

        raise Discourse::InvalidAccess
      end

      def workflow_references_dependency?(type, key)
        if @workflow_dependencies
          @workflow_dependencies[@node_id].include?("#{type}:#{key}")
        else
          DiscourseWorkflows::WorkflowDependency.exists?(
            workflow_id: @workflow.id,
            node_id: @node_id,
            dependency_type: type,
            dependency_key: key,
          )
        end
      end

      def sandbox_budget_tracker
        @sandbox_budget_tracker ||= DiscourseWorkflows::SandboxBudget.new(@flow_context)
      end

      def run_javascript_job(settings, _item_index)
        case settings.fetch("nodeMode")
        when DiscourseWorkflows::JsTaskRunnerSandbox::RUN_CODE
          run_javascript_code(settings)
        when DiscourseWorkflows::JsTaskRunnerSandbox::RUN_ONCE_FOR_ALL_ITEMS
          run_javascript_for_all_items(settings)
        when DiscourseWorkflows::JsTaskRunnerSandbox::RUN_ONCE_FOR_EACH_ITEM
          run_javascript_for_each_item(settings)
        else
          raise ArgumentError, "Unsupported JavaScript node mode: #{settings["nodeMode"]}"
        end
      end

      def run_javascript_code(settings)
        with_javascript_sandbox do |sandbox|
          declare_additional_properties(sandbox, settings["additionalProperties"])
          raw_javascript_result(sandbox, settings.fetch("code"))
        end
      end

      def run_javascript_for_all_items(settings)
        with_javascript_sandbox do |sandbox|
          setup_code_sandbox!(
            sandbox,
            input_items,
            @parameters,
            input_context,
            item_alias: input_items.first || { "json" => {} },
          )
          declare_additional_properties(
            sandbox,
            { "items" => input_items }.merge(settings["additionalProperties"] || {}),
          )
          raw_javascript_result(sandbox, settings.fetch("code"))
        end
      end

      def run_javascript_for_each_item(settings)
        chunk = settings["chunk"] || {}
        start_index = chunk.fetch("startIndex") { 0 }.to_i
        end_index = start_index + chunk.fetch("count") { input_items.length }.to_i

        with_javascript_sandbox do |sandbox|
          setup_code_sandbox!(
            sandbox,
            input_items,
            @parameters,
            input_context,
            item_alias: input_items[start_index] || { "json" => {} },
          )
          declare_additional_properties(sandbox, settings["additionalProperties"])

          input_items[start_index...end_index].each_with_index.filter_map do |item, offset|
            item_index = start_index + offset
            sandbox.rebind_code_item(item, item_index: item_index)
            sandbox.eval("item = $input.item;")
            result = raw_javascript_result(sandbox, settings.fetch("code"))
            next if result.nil?

            result
          end
        end
      end

      def with_javascript_sandbox(capture_logs: true)
        sandbox =
          JsSandbox.new(
            @resolver_context,
            user: @user,
            vars: @vars,
            capture_logs: capture_logs,
            budget_tracker: sandbox_budget_tracker,
          )
        yield sandbox
      ensure
        @log.merge(sandbox.log) if capture_logs && sandbox&.log
        sandbox&.dispose
      end

      def declare_additional_properties(sandbox, additional_properties)
        (additional_properties || {}).each do |name, value|
          name = name.to_s
          unless js_identifier?(name)
            raise ArgumentError, "Invalid JavaScript property name: #{name}"
          end

          sandbox.declare_json(name, value)
        end
      end

      def setup_code_sandbox!(sandbox, input_items, input_params, input_context, item_alias:)
        sandbox.declare_json("__allInputItems", input_items)
        sandbox.declare_json("__inputParams", input_params)
        sandbox.declare_json("__inputContext", input_context)
        sandbox.declare_json("__initialItem", item_alias)
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

          var $input = new __WorkflowCodeInput(__initialItem);
          var __itemIndex = 0;
          var item = $input.item;
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

      def raw_javascript_result(sandbox, code)
        result = evaluate_code(sandbox, code)

        case result["type"]
        when "null"
          nil
        when "undefined"
          JAVASCRIPT_UNDEFINED
        else
          result["value"]
        end
      end

      def js_identifier?(name)
        name.match?(/\A[$A-Za-z_][$0-9A-Za-z_]*\z/)
      end

      def item_index_for(item, input_index: 0)
        @item_indexes_by_input_object_id ||=
          @input_groups.each_with_object({}) do |(index, items), result|
            result[index] = items.each_with_index.to_h do |entry, item_index|
              [entry.object_id, item_index]
            end
          end
        @item_indexes_by_input_object_id.fetch(input_index) { {} }.fetch(item.object_id, 0)
      end

      def normalize_input_groups(input_groups, input_items)
        groups = input_groups || { 0 => input_items }
        has_indexed_inputs =
          groups.keys.any? { |key| key.to_s.match?(/\Ainput_\d+\z/) || key.is_a?(Integer) }
        groups.each_with_object({}) do |(key, items), result|
          next if has_indexed_inputs && key.to_s == "main"

          result[input_index(key)] = items || []
        end
      end

      def input_index(input_key)
        return input_key if input_key.is_a?(Integer)

        value = input_key.to_s
        return 0 if value == "main"

        match = value.match(/\Ainput_(\d+)\z/)
        return match[1].to_i - 1 if match

        value.to_i
      end

      def raw_expressions?(options)
        options&.fetch(:raw_expressions, false)
      end

      def raw_parameter_path(path)
        segments = path.split(".").reject(&:blank?)
        return MISSING if segments.empty?
        return MISSING unless @parameters.key?(segments.first)

        if segments.one?
          @parameters[segments.first]
        else
          dig_parameter_path(@parameters[segments.first], segments.drop(1))
        end
      end

      def ensure_parameter_type(value, type, parameter_name)
        return value if type.nil? || value.nil? || value.equal?(MISSING)

        case type
        when :integer
          value.to_i
        when :float, :number
          value.to_f
        when :string
          value.to_s
        when :boolean
          ActiveModel::Type::Boolean.new.cast(value)
        else
          raise ArgumentError, "Unsupported parameter type for #{parameter_name}: #{type.inspect}"
        end
      end

      def resolve_parameter(name, schema)
        return @parameters[name] if no_data_expression?(schema)

        if condition_builder_schema?(schema)
          conditions = @parameters.fetch("conditions") { [] }
          combinator = @parameters.fetch("combinator") { "and" }
          options = @parameters.fetch("options") { {} }
          result =
            Executor::FilterParameter.execute_filter(conditions, combinator, options, @resolver)
          @condition_details.concat(result["details"])
          result["passed"]
        else
          resolve_parameter_value(@parameters[name], schema)
        end
      end

      def resolve_parameter_value(value, schema = nil)
        return value if no_data_expression?(schema)
        return resolve_fixed_collection_value(value, schema) if fixed_collection_schema?(schema)

        case value
        when Hash
          resolve_hash_parameter_value(value, schema)
        when Array
          item_schema = schema_value(schema, :item_schema)
          value.map { |entry| resolve_parameter_value(entry, item_schema) }
        else
          @resolver.resolve(value)
        end
      end

      def resolve_hash_parameter_value(value, schema)
        fields = schema_value(schema, :fields) || {}

        value.transform_values.with_index do |nested_value, index|
          key = value.keys[index]
          nested_schema = fields[key.to_sym] || fields[key.to_s]
          resolve_parameter_value(nested_value, nested_schema)
        end
      end

      def resolve_fixed_collection_value(value, schema)
        unless value.is_a?(Hash)
          return(
            resolve_fixed_collection_group_value(value, first_fixed_collection_row_schema(schema))
          )
        end

        value.transform_values.with_index do |group_value, index|
          group_name = value.keys[index]
          row_schema = fixed_collection_row_schema(schema, group_name)
          resolve_fixed_collection_group_value(group_value, row_schema)
        end
      end

      def resolve_fixed_collection_group_value(value, row_schema)
        case value
        when Array
          value.map { |row| resolve_parameter_value(row, { type: :object, fields: row_schema }) }
        when Hash
          resolve_parameter_value(value, { type: :object, fields: row_schema })
        else
          resolve_parameter_value(value)
        end
      end

      def fixed_collection_row_schema(schema, group_name)
        group =
          Array(schema_value(schema, :options)).find do |option|
            (schema_value(option, :name) || "").to_s == group_name.to_s
          end

        schema_value(group, :values) || {}
      end

      def first_fixed_collection_row_schema(schema)
        schema_value(Array(schema_value(schema, :options)).first, :values) || {}
      end

      def resolve_parameter_path(path)
        segments = path.split(".").reject(&:blank?)
        return MISSING if segments.empty?

        name = segments.first
        schema = @property_schema[name.to_sym] || @property_schema[name]
        if !@parameters.key?(name)
          return resolve_parameter(name, schema) if condition_builder_schema?(schema)

          return MISSING
        end

        resolved = resolve_parameter(name, schema)
        return resolved if segments.one?

        dig_parameter_path(resolved, segments.drop(1))
      end

      def dig_parameter_path(value, segments)
        segments.reduce(value) do |current, segment|
          case current
          when Hash
            return MISSING unless current.key?(segment)

            current[segment]
          when Array
            return MISSING unless segment.match?(/\A\d+\z/)

            current.fetch(segment.to_i) { return MISSING }
          else
            return MISSING
          end
        end
      end

      def condition_builder_schema?(schema)
        schema.is_a?(Hash) && schema.dig(:ui, :control) == :condition_builder
      end

      def fixed_collection_schema?(schema)
        schema_value(schema, :type) == :fixed_collection
      end

      def no_data_expression?(schema)
        schema_value(schema, :no_data_expression) == true
      end

      def schema_value(schema, key)
        return nil unless schema.respond_to?(:[])

        schema[key] || schema[key.to_s]
      end

      def resolve_all_parameters
        @parameters.transform_values.with_index do |_value, index|
          name = @parameters.keys[index]
          schema = @property_schema[name.to_sym] || @property_schema[name]
          resolve_parameter(name, schema)
        end
      end

      def credential_id_for(slot)
        credential = @credentials[slot.to_s]
        credential["id"].to_s if credential
      end

      def declared_credential_slot?(slot)
        credential_definition(slot).present?
      end

      def credential_type_allowed?(slot, credential_type)
        credential_types = NodeData.credential_types_for(credential_definition(slot))
        credential_types.include?(credential_type.to_s)
      end

      def credential_definition(slot)
        @credential_schema.find { |definition| definition["name"] == slot.to_s }
      end
    end
  end
end
