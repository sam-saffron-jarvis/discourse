# Workflow Runtime Boundaries

Workflow nodes and external integrations use public execution APIs only. The node-facing API
tracks the `IExecuteFunctions` contract by behavior and lifecycle semantics, translated into Ruby
naming and Ruby call patterns.

Nodes resolve parameters by input item index, not by passing item objects around:

```ruby
config = exec_ctx.get_node_parameters(0)
value = exec_ctx.get_node_parameter("message", item_index)
rows = exec_ctx.get_fixed_collection_rows("headers", item_index)
```

Runtime facilities are exposed through the execution context:

- Input data: `input_items`, `inputs`, `get_input_data`
- Parameters: `get_node_parameter`, `get_node_parameters`
- Credentials: `credential_reference?`, `get_credentials`
- Task runners: `start_job`, `continue_on_fail`, `helpers`
- Waiting/resume: `put_execution_to_wait`, `resume_action_id`
- Expressions, metadata, and hints: `evaluate_expression`, `set_metadata`, `add_execution_hints`

Helpers stay Ruby-idiomatic under `exec_ctx.helpers`, for example `normalize_items` and
`get_data_table_proxy`. Do not introduce camelCase Ruby APIs just to mirror TypeScript spelling.

Nodes can ask `exec_ctx` for runtime-provided handles such as resume action IDs and resume URLs, then pass those handles to another system. Waiting webhook nodes implement `webhook(webhook_ctx)` and return `DiscourseWorkflows::WebhookResponse` objects with either an HTTP response body or positional `workflow_data` output arrays. They must not call execution storage, waiting execution lookup, claim, or resume internals directly.

The workflow runtime owns waiting execution lookup, signature validation, atomic claiming, resume dispatch, and final HTTP response assembly. Node webhook methods own only node-local work such as rendering a node-specific response, validating submitted node data, and returning output items for the runtime to resume with.

External integrations that receive an interactive response use `DiscourseWorkflows::InteractiveResume`. That class owns action token parsing, signature validation, waiting node checks, atomic claiming, and resuming the execution.

Runtime internals such as `DiscourseWorkflows::WaitingExecution`,
`DiscourseWorkflows::Execution.claim_for_resume`, and `DiscourseWorkflows::Executor.resume`
remain implementation details for workflow core services, jobs, controllers, and stores.

Trigger nodes follow the same boundary through `trigger_ctx`, which tracks n8n's
`ITriggerFunctions` contract in Ruby naming. Trigger nodes implement `trigger(trigger_ctx)` and
use only context methods for runtime behavior:

- Parameters: `get_node_parameter`
- Timezone and mode: `get_timezone`, `get_mode`, `get_activation_mode`
- Persistent node state: `get_workflow_static_data(:node)`
- Scheduling and output: `helpers.register_cron`, `helpers.return_json_array`, `emit`

Schedule-like trigger nodes declare their configuration and convert it to cron registrations, but
the runtime owns workflow lookup, static-data persistence, deduplication, job enqueueing, and
dispatch. Nodes must not call `Workflow`, `NodeData`, `TriggerDispatcher`, jobs, published-trigger
lookup, or static-data storage directly.

Specs should assert observable node and workflow behavior: output items, waiting status, resume
payloads, validation errors, and execution metadata. Avoid tests whose only purpose is to police
which internal helper a node did or did not call.
