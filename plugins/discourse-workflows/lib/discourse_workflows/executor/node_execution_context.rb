# frozen_string_literal: true

module DiscourseWorkflows
  class Executor
    class NodeExecutionContext
      attr_reader :user,
                  :vars,
                  :expression_errors,
                  :condition_details,
                  :log,
                  :execution_id,
                  :resume_token,
                  :node_id,
                  :waiting_until

      def initialize(
        input_items:,
        input_groups: nil,
        parameters: nil,
        credentials: {},
        settings: {},
        webhook_id: nil,
        configuration: nil,
        property_schema: {},
        node_context: {},
        user: nil,
        resolver: nil,
        vars: nil,
        workflow: nil,
        execution_id: nil,
        resume_token: nil,
        node_id: nil,
        flow_context: nil,
        resolver_context: nil,
        workflow_dependencies: nil
      )
        @input_groups = normalize_input_groups(input_groups, input_items)
        @input_items = @input_groups[0] || []
        split =
          NodeData.split(
            parameters: parameters || configuration || {},
            credentials: credentials,
            settings: settings,
            webhook_id: webhook_id,
          )
        @parameters = split["parameters"]
        @credentials = NodeData.normalize_credentials(split["credentials"])
        @settings = split["settings"]
        @webhook_id = split["webhook_id"]
        @configuration = @parameters
        @property_schema = property_schema
        @node_context = node_context
        @user = user
        @resolver = resolver
        @vars = vars
        @workflow = workflow
        @execution_id = execution_id
        @resume_token = resume_token
        @node_id = node_id
        @flow_context = flow_context || {}
        @resolver_context = resolver_context || {}
        @expression_errors = []
        @condition_details = []
        @log = StepLog.new
        @waiting = false
        @waiting_until = nil
        @workflow_dependencies = workflow_dependencies
      end

      def get_context(scope = :flow)
        case scope
        when :flow
          @flow_context
        when :node
          @node_context
        else
          raise ArgumentError, "Unknown context scope: #{scope}. Use :flow or :node"
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

      def with_sandbox(capture_logs: false)
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

      def get_parameter(name, item)
        name_str = name.to_s
        schema = @property_schema[name.to_sym] || @property_schema[name_str]
        with_item(item) { resolve_parameter(name_str, schema) }
      end

      def get_parameters(item)
        with_item(item) { resolve_all_parameters }
      end

      def data_table(id)
        id = id.to_s
        ensure_data_table_access!(id)
        table = DiscourseWorkflows::DataTable.find(id)
        DiscourseWorkflows::DataTables::NodeProxy.new(
          DiscourseWorkflows::DataTables::Facade.new(table),
        )
      end

      def get_credential(credential_id_or_slot)
        raise ArgumentError, "credential_id is required" if credential_id_or_slot.blank?

        credential_id = credential_id_for(credential_id_or_slot) || credential_id_or_slot.to_s
        ensure_credential_access!(credential_id)
        credential = DiscourseWorkflows::Credential.find_by(id: credential_id)
        raise Discourse::InvalidAccess if credential.nil?

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

      def waiting?
        @waiting
      end

      def with_item(item)
        @resolver.with_item(item, item_index: item_index_for(item)) { yield }
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

      def ensure_credential_access!(credential_id)
        expected_credential_id = credential_id_for("auth")
        if @workflow && @node_id
          return if workflow_references_dependency?("credential_id", credential_id)
        elsif expected_credential_id == credential_id
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

      def item_index_for(item)
        @item_indexes_by_object_id ||=
          input_items.each_with_index.to_h { |entry, index| [entry.object_id, index] }
        @item_indexes_by_object_id.fetch(item.object_id, 0)
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

      def resolve_parameter(name, schema)
        if schema.is_a?(Hash) && schema.dig(:ui, :control) == :condition_builder
          conditions = @parameters.fetch("conditions") { [] }
          combinator = @parameters.fetch("combinator") { "and" }
          options = @parameters.fetch("options") { {} }
          result =
            Executor::FilterParameter.execute_filter(conditions, combinator, options, @resolver)
          @condition_details.concat(result["details"])
          result["passed"]
        else
          credential_parameters = NodeData.credential_parameters(@credentials)
          return credential_parameters[name] if credential_parameters.key?(name)

          @resolver.resolve(@parameters[name])
        end
      end

      def resolve_all_parameters
        @resolver.resolve_hash(@parameters).merge(NodeData.credential_parameters(@credentials))
      end

      def credential_id_for(slot)
        credential = @credentials[slot.to_s]
        credential["id"].to_s if credential
      end
    end
  end
end
