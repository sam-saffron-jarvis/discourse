# frozen_string_literal: true

RSpec.describe DiscourseWorkflows::Nodes::SendChatMessage::V1 do
  fab!(:channel, :chat_channel)

  before { SiteSetting.chat_enabled = true }

  describe "#execute" do
    it "resolves message expressions for each input item" do
      input_items = [
        { "json" => { "text" => "First message" } },
        { "json" => { "text" => "Second message" } },
      ]
      parameters = {
        "channel_id" => channel.id.to_s,
        "message" => "={{ $json.text }}",
      }
      resolver_context = { "$json" => {} }
      sandbox = DiscourseWorkflows::JsSandbox.new(resolver_context)
      resolver = DiscourseWorkflows::ExpressionResolver.new(resolver_context, sandbox: sandbox)
      exec_ctx =
        DiscourseWorkflows::Executor::NodeExecutionContext.new(
          input_items: input_items,
          resolver: resolver,
          parameters: parameters,
          property_schema: described_class.property_schema,
          node_identifier: described_class.identifier,
          resolver_context: resolver_context,
        )

      output = described_class.new(parameters: parameters).execute(exec_ctx)

      expect(output.first.map { |item| item["json"]["message"] }).to eq(
        ["First message", "Second message"],
      )
      expect(channel.chat_messages.order(:id).last(2).map(&:message)).to eq(
        ["First message", "Second message"],
      )
    ensure
      resolver&.dispose
      sandbox&.dispose
    end
  end
end
