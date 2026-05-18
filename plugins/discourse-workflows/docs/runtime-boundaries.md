# Workflow Runtime Boundaries

Workflow nodes and external integrations use public execution APIs only.

Nodes can ask `exec_ctx` for runtime-provided handles such as resume action IDs and resume URLs, then pass those handles to another system. They must not call execution storage, waiting execution lookup, claim, or resume internals directly.

External integrations that receive an interactive response use `DiscourseWorkflows::InteractiveResume`. That class owns action token parsing, signature validation, waiting node checks, atomic claiming, and resuming the execution.

Runtime internals such as `DiscourseWorkflows::WaitingExecution`,
`DiscourseWorkflows::Execution.claim_for_resume`, and `DiscourseWorkflows::Executor.resume`
remain implementation details for workflow core services, jobs, controllers, and stores.
