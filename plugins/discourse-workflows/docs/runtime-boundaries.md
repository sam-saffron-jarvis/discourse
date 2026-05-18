# Workflow Runtime Boundaries

Workflow nodes and external integrations use public execution APIs only.

Nodes can ask `exec_ctx` for runtime-provided handles such as resume action IDs and resume URLs, then pass those handles to another system. Waiting webhook nodes implement `webhook(webhook_ctx)` and return `DiscourseWorkflows::WebhookResponse` objects with either an HTTP response body or n8n-style `workflow_data` output arrays. They must not call execution storage, waiting execution lookup, claim, or resume internals directly.

The workflow runtime owns waiting execution lookup, signature validation, atomic claiming, resume dispatch, and final HTTP response assembly. Node webhook methods own only node-local work such as rendering a node-specific response, validating submitted node data, and returning output items for the runtime to resume with.

External integrations that receive an interactive response use `DiscourseWorkflows::InteractiveResume`. That class owns action token parsing, signature validation, waiting node checks, atomic claiming, and resuming the execution.

Runtime internals such as `DiscourseWorkflows::WaitingExecution`,
`DiscourseWorkflows::Execution.claim_for_resume`, and `DiscourseWorkflows::Executor.resume`
remain implementation details for workflow core services, jobs, controllers, and stores.
