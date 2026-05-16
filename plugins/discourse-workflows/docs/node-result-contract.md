# Node execution result contract

Nodes should return `DiscourseWorkflows::Executor::NodeResult` from `execute`.

Use the execution context helpers for common output shapes:

```ruby
def execute(exec_ctx)
  items = exec_ctx.input_items.map { |item| wrap(process(item)) }
  exec_ctx.success(items)
end
```

```ruby
def execute(exec_ctx)
  true_items, false_items = exec_ctx.input_items.partition { |item| keep?(item) }
  exec_ctx.branch("true" => true_items, "false" => false_items)
end
```

```ruby
def execute(exec_ctx)
  exec_ctx.pass_through
end
```

`exec_ctx.success(items)` returns items on the primary `main` output. `exec_ctx.items(items)` is an alias for nodes that only transform item arrays. `exec_ctx.branch(...)` returns explicit named outputs and should match the node's declared output keys. For simple ordered branches, `exec_ctx.branch(first_output_items, second_output_items)` maps arrays to the declared output port order.

The executor still accepts the legacy n8n-style raw output array shape, for example `[[item]]` or `[true_items, false_items]`, and normalizes it to `NodeResult`. New Ruby node implementations should prefer the helpers so the contract is visible from the `execute` method.
