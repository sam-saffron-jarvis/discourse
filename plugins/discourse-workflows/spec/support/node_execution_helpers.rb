# frozen_string_literal: true

module NodeExecutionHelpers
  def execute_node_result(
    configuration:,
    item: nil,
    input_items: nil,
    input_groups: nil,
    node_context: nil,
    &block
  )
    item = { "json" => {} } if item.nil? && input_items.nil?
    input_items = input_items || [item]
    action = described_class.new(parameters: configuration)
    resolver_context = { "$json" => input_items.first&.dig("json") || {} }
    sandbox = DiscourseWorkflows::JsSandbox.new(resolver_context)
    resolver = DiscourseWorkflows::ExpressionResolver.new(resolver_context, sandbox: sandbox)
    kwargs = {
      input_items: input_items,
      input_groups: input_groups,
      resolver: resolver,
      parameters: configuration,
      property_schema: described_class.property_schema,
      resolver_context: resolver_context,
    }
    kwargs[:node_context] = node_context if node_context

    ctx = DiscourseWorkflows::Executor::NodeExecutionContext.new(**kwargs)
    raw = action.execute(ctx)
    block&.call(ctx)
    return raw if raw.is_a?(DiscourseWorkflows::Executor::NodeResult)

    DiscourseWorkflows::Executor::NodeResult.from_output_arrays(raw, ports: described_class.ports)
  ensure
    resolver&.dispose
    sandbox&.dispose
  end

  def execute_node(configuration:, item: { "json" => {} })
    result = execute_node_result(configuration: configuration, item: item)
    result.primary_items(ports: described_class.ports).first["json"]
  end
end

RSpec.configure { |config| config.include NodeExecutionHelpers }
