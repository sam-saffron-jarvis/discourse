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
    node_credentials = configuration.fetch("credentials") { {} }
    node_parameters = configuration.except("credentials")
    ports = described_class.ports(node_parameters)
    action = described_class.new(parameters: node_parameters, credentials: node_credentials)
    resolver_context = { "$json" => input_items.first&.dig("json") || {} }
    sandbox = DiscourseWorkflows::JsSandbox.new(resolver_context)
    resolver = DiscourseWorkflows::ExpressionResolver.new(resolver_context, sandbox: sandbox)
    kwargs = {
      input_items: input_items,
      input_groups: input_groups,
      resolver: resolver,
      parameters: node_parameters,
      credentials: node_credentials,
      property_schema: described_class.property_schema,
      credential_schema: described_class.credentials,
      resolver_context: resolver_context,
      output_ports: ports,
    }
    kwargs[:node_context] = node_context if node_context

    ctx = DiscourseWorkflows::Executor::NodeExecutionContext.new(**kwargs)
    raw = action.execute(ctx)
    block&.call(ctx)
    return raw if raw.is_a?(DiscourseWorkflows::Executor::NodeResult)

    DiscourseWorkflows::Executor::NodeResult.from_output_arrays(raw, ports: ports)
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
