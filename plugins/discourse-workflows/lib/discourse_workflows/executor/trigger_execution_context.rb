# frozen_string_literal: true

module DiscourseWorkflows
  class Executor
    class TriggerExecutionContext
      MISSING = Object.new.freeze
      MAX_DEDUPLICATION_KEYS = 200

      attr_reader :published_trigger,
                  :node_type_class,
                  :now,
                  :emitted_trigger_data,
                  :node_id,
                  :node_identifier

      def initialize(
        published_trigger:,
        node_type_class:,
        mode: :normal,
        activation_mode: :init,
        now: Time.current.utc,
        dispatch: :enqueue,
        tick: false,
        user: nil
      )
        @published_trigger = published_trigger
        @node_type_class = node_type_class
        @mode = mode.to_s
        @activation_mode = activation_mode.to_s
        @now = now
        @dispatch = dispatch
        @tick = tick
        @user = user
        @node_id = published_trigger.trigger_node_id.to_s
        @node_identifier = node_value("type").to_s
        @snapshot = WorkflowSnapshot.from_version(workflow, workflow_version)
        @static_data = workflow.node_static_data(node_id).deep_dup
        @emitted_trigger_data = []
      end

      def get_node_parameter(parameter_name, default = nil, _options = {})
        value = parameter_value(parameter_name)
        value.equal?(MISSING) ? default : value
      end

      def get_timezone
        DiscourseWorkflows::WorkflowTimezone.for(workflow:, workflow_version:)
      end

      def get_workflow_static_data(type)
        raise ArgumentError, "Only node static data is supported" unless type.to_s == "node"

        @static_data
      end

      def get_mode
        @mode
      end

      def get_activation_mode
        @activation_mode
      end

      def get_workflow
        WorkflowView.from_workflow(workflow, name: workflow_version.name)
      end

      def get_node
        NodeView.from_snapshot_node(
          @snapshot.find_node(node_id),
          include_node_parameters: true,
          include_credentials: true,
          include_webhook_id: true,
        )
      end

      def get_child_nodes(node_name, options = {})
        graph_nodes(
          @snapshot.child_nodes(node_name, connection_type: "main", depth: -1),
          include_node_parameters: graph_option(options, :include_node_parameters, false),
        )
      end

      def get_parent_nodes(node_name, options = {})
        graph_nodes(
          @snapshot.parent_nodes(
            node_name,
            connection_type: graph_option(options, :connection_type, "main"),
            depth: graph_option(options, :depth, -1),
          ),
          include_node_parameters: graph_option(options, :include_node_parameters, false),
        )
      end

      def workflow_id
        workflow.id
      end

      def workflow_version_id
        workflow_version.id
      end

      def helpers
        @helpers ||= Helpers.new(self)
      end

      def tick?
        @tick
      end

      def emit(data, deduplication_key: nil)
        trigger_data = trigger_data_from(data)
        return if trigger_data.blank?
        return if deduplicated?(deduplication_key)

        if deduplication_key.present?
          keys = Array.wrap(@static_data["triggered_occurrences"])
          @static_data["triggered_occurrences"] = keys.last(MAX_DEDUPLICATION_KEYS - 1) +
            [deduplication_key]
          @static_data["last_triggered_at"] = now.utc.iso8601
        end

        case @dispatch
        when :enqueue
          DiscourseWorkflows::TriggerDispatcher.enqueue(published_trigger, trigger_data:)
        when :execute
          DiscourseWorkflows::TriggerDispatcher.execute(
            published_trigger,
            trigger_data:,
            user: @user,
          )
        when :collect
          @emitted_trigger_data << trigger_data
        when :none
          nil
        end
      end

      def persist_static_data!
        workflow.update_node_static_data!(node_id, @static_data)
      end

      private

      def workflow
        published_trigger.workflow
      end

      def workflow_version
        published_trigger.workflow_version
      end

      def graph_nodes(nodes, include_node_parameters:)
        Array
          .wrap(nodes)
          .filter_map do |node|
            NodeView.from_snapshot_node(node, include_node_parameters: include_node_parameters)
          end
      end

      def graph_option(options, key, default)
        options = {} unless options.respond_to?(:[])
        options[key] || options[key.to_s] || default
      end

      def parameters
        @parameters ||= DiscourseWorkflows::NodeData.parameters(published_trigger.trigger_node)
      end

      def parameter_value(parameter_name)
        segments = parameter_name.to_s.split(".").reject(&:blank?)
        return MISSING if segments.empty?

        segments.reduce(parameters) do |current, segment|
          case current
          when Hash
            current.fetch(segment) { current.fetch(segment.to_sym, MISSING) }
          when Array
            return MISSING unless segment.match?(/\A\d+\z/)

            current.fetch(segment.to_i) { return MISSING }
          else
            return MISSING
          end
        end
      end

      def node_value(key)
        DiscourseWorkflows::NodeData.read(published_trigger.trigger_node, key)
      end

      def deduplicated?(deduplication_key)
        deduplication_key.present? &&
          Array.wrap(@static_data["triggered_occurrences"]).include?(deduplication_key)
      end

      def trigger_data_from(data)
        output_arrays = Array.wrap(data)
        first_output = output_arrays.first
        first_item = Array.wrap(first_output).first

        if first_item.is_a?(Hash) && first_item.key?("json")
          first_item["json"]
        elsif first_item.is_a?(Hash)
          first_item.deep_stringify_keys
        else
          {}
        end
      end

      class Helpers
        def initialize(context)
          @context = context
        end

        def return_json_array(json_data)
          Array.wrap(json_data).map { |data| DiscourseWorkflows::Item.wrap(data) }
        end

        def register_cron(cron)
          return unless @context.tick?

          expression = cron[:expression] || cron["expression"]
          scheduled_time = @context.now.in_time_zone(@context.get_timezone)
          return unless DiscourseWorkflows::CronParser.matches?(expression, scheduled_time)

          yield @context.now if block_given?
        end
      end
    end
  end
end
