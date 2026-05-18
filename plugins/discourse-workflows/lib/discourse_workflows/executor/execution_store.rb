# frozen_string_literal: true

module DiscourseWorkflows
  class Executor
    class ExecutionStore
      MAX_EXECUTION_DATA_SIZE = 5.megabytes
      MAX_STEP_IO_SIZE = 128.kilobytes
      MAX_STEP_STRING_BYTES = 16.kilobytes
      MAX_STEP_COLLECTION_SIZE = 50
      MAX_STEP_IO_DEPTH = 8

      delegate :workflow, :trigger_data, to: :@execution_context

      attr_reader :trigger_node_id, :execution, :workflow_snapshot

      def initialize(trigger_node_id:, execution_context:, execution_mode:, options:)
        @trigger_node_id = trigger_node_id.to_s
        @execution_context = execution_context
        @execution_mode = execution_mode
        @options = options
        @workflow_snapshot = nil
      end

      def start!
        @workflow_snapshot =
          if @options.workflow_version
            WorkflowSnapshot.from_version(workflow, @options.workflow_version)
          else
            WorkflowSnapshot.from_workflow(workflow, published: !@options.draft_execution)
          end
        @execution_context.use_workflow_nodes(
          @workflow_snapshot.to_h["nodes"],
          workflow_name: @workflow_snapshot.workflow_name,
        )
        @execution = create_execution!
        reset_collaborators!
        @execution
      end

      def resume!(execution)
        @execution = execution
        @execution_context.execution = execution
        restore_from!(execution.execution_data)
        @execution
      end

      def finish!(steps:)
        save!(steps)
        execution.update!(
          status: :success,
          finished_at: Time.current,
          run_time_ms: Execution.compute_run_time_ms(steps),
        )
        publish_execution_node_outputs(steps)
        execution
      end

      def fail!(error:, steps: [])
        save!(steps)
        execution.update!(
          status: :error,
          error: error.message.to_s.truncate(1000),
          finished_at: Time.current,
          run_time_ms: Execution.compute_run_time_ms(steps),
        )
        trigger_error_workflow(error, steps)
        execution
      end

      def create_execution_with_status(status, trigger_data: self.trigger_data)
        now = Time.current

        DiscourseWorkflows::Execution.create!(
          workflow: workflow,
          trigger_node_id: @trigger_node_id,
          status: status,
          trigger_data: trigger_data,
          execution_mode: @options.execution_mode,
          started_at: now,
          finished_at: now,
        )
      end

      def create_rate_limited_execution
        create_execution_with_status(:rate_limited, trigger_data: { "rate_limited" => true })
      end

      def pause_waiting_execution!(node:, waiting_until: nil, steps: [])
        execution.update!(
          status: :waiting,
          waiting_node_id: node.id,
          waiting_until: waiting_until,
          resume_token: @execution_context.resume_token,
        )
        save!(steps)
        publish_waiting_form_notification(node)
        execution
      end

      def clear_waiting_execution!
        execution.update!(
          status: :running,
          waiting_node_id: nil,
          waiting_until: nil,
          resume_token: nil,
          timeout_action: nil,
        )
      end

      private

      def create_execution!
        DiscourseWorkflows::Execution.create!(
          workflow: workflow,
          trigger_node_id: @trigger_node_id,
          status: :running,
          trigger_data: trigger_data,
          execution_mode: @execution_mode,
          started_at: Time.current,
        )
      end

      def reset_collaborators!
        @execution_context.execution = @execution
        @execution_context.reset!
      end

      def restore_from!(execution_data)
        @workflow_snapshot =
          if execution_data&.workflow_data.present?
            WorkflowSnapshot.new(execution_data.workflow_data)
          else
            WorkflowSnapshot.from_workflow(workflow, published: true)
          end
        @execution_context.use_workflow_nodes(
          @workflow_snapshot.to_h["nodes"],
          workflow_name: @workflow_snapshot.workflow_name,
        )
        @execution_context.restore!(
          context: execution_data&.context_data || {},
          node_contexts: execution_data&.node_contexts || {},
        )
      end

      def save!(steps)
        entries = steps_to_entries(steps)

        ed = execution.execution_data || execution.build_execution_data
        ed.update!(
          data: serialized_execution_data(entries),
          workflow_data: @workflow_snapshot&.to_h,
        )
      end

      def serialized_execution_data(entries)
        truncated_context = { "__truncated" => true }
        json_data =
          execution_data_payload(
            entries,
            @execution_context.context,
            @execution_context.node_contexts,
          )
        return json_data if json_data.bytesize <= MAX_EXECUTION_DATA_SIZE

        log_oversized_execution_data("exceeds #{MAX_EXECUTION_DATA_SIZE} bytes, truncating context")
        json_data = execution_data_payload(entries, truncated_context)
        return json_data if json_data.bytesize <= MAX_EXECUTION_DATA_SIZE

        log_oversized_execution_data(
          "still exceeds #{MAX_EXECUTION_DATA_SIZE} bytes, truncating entries",
        )
        json_data = execution_data_payload(compact_entries(entries), truncated_context)
        return json_data if json_data.bytesize <= MAX_EXECUTION_DATA_SIZE

        log_oversized_execution_data(
          "still exceeds #{MAX_EXECUTION_DATA_SIZE} bytes after all truncation attempts, storing minimal record",
        )
        execution_data_payload({}, truncated_context)
      end

      def execution_data_payload(entries, context, node_contexts = {})
        { "entries" => entries, "context" => context, "node_contexts" => node_contexts }.to_json
      end

      def log_oversized_execution_data(message)
        Rails.logger.warn(
          "discourse-workflows: execution data for execution #{execution.id} #{message}",
        )
      end

      def steps_to_entries(steps)
        steps
          .group_by(&:node_id)
          .transform_values { |node_steps| node_steps.map { |step| step_to_entry(step) } }
      end

      def step_to_entry(step)
        entry = step.to_h
        entry["input"] = bounded_step_io(entry["input"]) if entry.key?("input")
        entry["output"] = bounded_step_io(entry["output"]) if entry.key?("output")
        entry
      end

      def bounded_step_io(value)
        bounded_value = bound_execution_value(value)
        return bounded_value if bounded_value.to_json.bytesize <= MAX_STEP_IO_SIZE

        truncated_value(value, MAX_STEP_IO_SIZE, "step_io_size_limit")
      end

      def bound_execution_value(value, depth = 0)
        return truncated_value(value, nil, "step_io_depth_limit") if depth >= MAX_STEP_IO_DEPTH

        case value
        when String
          bound_string(value)
        when Array
          bound_array(value, depth)
        when Hash
          bound_hash(value, depth)
        else
          value
        end
      end

      def bound_string(value)
        return value if value.bytesize <= MAX_STEP_STRING_BYTES

        {
          "__truncated" => true,
          "__reason" => "step_string_size_limit",
          "__original_bytes" => value.bytesize,
          "preview" => value.byteslice(0, MAX_STEP_STRING_BYTES).scrub,
        }
      end

      def bound_array(value, depth)
        kept_items =
          value
            .first(MAX_STEP_COLLECTION_SIZE)
            .map { |item| bound_execution_value(item, depth + 1) }
        return kept_items if value.size <= MAX_STEP_COLLECTION_SIZE

        kept_items << truncated_value(value, nil, "step_collection_size_limit")
      end

      def bound_hash(value, depth)
        kept_pairs =
          value
            .first(MAX_STEP_COLLECTION_SIZE)
            .to_h { |key, hash_value| [key, bound_execution_value(hash_value, depth + 1)] }
        return kept_pairs if value.size <= MAX_STEP_COLLECTION_SIZE

        kept_pairs.merge(
          "__truncated" => true,
          "__reason" => "step_collection_size_limit",
          "__omitted_keys" => value.size - MAX_STEP_COLLECTION_SIZE,
        )
      end

      def truncated_value(value, max_bytes, reason)
        result = { "__truncated" => true, "__reason" => reason, "__class" => value.class.name }
        result["__max_bytes"] = max_bytes if max_bytes
        result["__original_size"] = value.size if value.respond_to?(:size)
        result
      end

      def compact_entries(entries)
        entries.transform_values do |node_steps|
          Array(node_steps).map do |step|
            step.except("input", "output").merge(
              "input" => truncated_value(step["input"] || [], nil, "execution_data_size_limit"),
              "output" => truncated_value(step["output"] || [], nil, "execution_data_size_limit"),
            )
          end
        end
      end

      def trigger_error_workflow(error, steps)
        ErrorWorkflowTrigger.new(
          workflow,
          steps,
          execution: execution,
          execution_mode: @options.execution_mode,
        ).trigger_error_workflow(error)
      end

      def publish_waiting_form_notification(node)
        return unless node.type == "action:form"
        return if @workflow_snapshot.nil?

        trigger_node = @workflow_snapshot.find_node(@trigger_node_id)
        return unless trigger_node&.type == "trigger:form"

        channel = DiscourseWorkflows::WaitingExecution.form_channel(execution)
        return if channel.blank?

        MessageBus.publish(
          channel,
          {
            status: "waiting_for_form",
            form_waiting_url: DiscourseWorkflows::WaitingExecution.form_waiting_url(execution),
            form_submit_url: DiscourseWorkflows::WaitingExecution.form_waiting_url(execution),
            form_status_url: DiscourseWorkflows::WaitingExecution.form_status_url(execution),
          },
        )
      end

      def publish_execution_node_outputs(steps)
        outputs =
          steps.each_with_object({}) do |step, result|
            first_json = (step.output || []).dig(0, "json") if step.success?
            result[step.node_id] = first_json if first_json.present?
          end

        return if outputs.empty?

        MessageBus.publish(
          "/discourse-workflows/workflow/#{workflow.id}",
          { type: "execution_completed", last_execution_node_outputs: outputs },
          group_ids: [Group::AUTO_GROUPS[:admins]],
        )
      end
    end
  end
end
