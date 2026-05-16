# Node output contract

Nodes must return the n8n-compatible positional output shape from `execute`:

```ruby
Array<Array<Item>>
```

Each inner array is one output port by index. Output labels are node metadata for the editor; runtime routing is positional.

Single-output nodes return one inner array:

```ruby
def execute(exec_ctx)
  items = exec_ctx.input_items.map { |item| wrap(process(item)) }
  [items]
end
```

Pass-through nodes return the current input items as the first output:

```ruby
def execute(exec_ctx)
  [exec_ctx.input_items]
end
```

Branching nodes return one item array per output port, in declared output order:

```ruby
def execute(exec_ctx)
  true_items, false_items = exec_ctx.input_items.partition { |item| keep?(item) }
  [true_items, false_items]
end
```

Do not return named output hashes or Discourse-specific result objects from node `execute`.
