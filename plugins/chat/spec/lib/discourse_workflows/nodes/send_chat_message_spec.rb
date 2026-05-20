# frozen_string_literal: true

RSpec.describe DiscourseWorkflows::Nodes::SendChatMessage::V1 do
  fab!(:channel, :chat_channel)

  before { SiteSetting.chat_enabled = true }

  describe ".load_options_context" do
    fab!(:other_channel) { Fabricate(:chat_channel, name: "Announcements") }
    fab!(:closed_channel) { Fabricate(:chat_channel, name: "Closed", status: :closed) }
    fab!(:dm_channel, :direct_message_channel)

    def load_options(filter: nil)
      context =
        DiscourseWorkflows::LoadOptionsContext.new(
          method_name: "chat_channels",
          filter: filter,
          node_class: described_class,
        )

      described_class.load_options_context(context)
    end

    it "returns open public channels with id and name" do
      ids = load_options.map { |option| option[:id] }

      expect(ids).to include(channel.id, other_channel.id)
      expect(ids).not_to include(closed_channel.id, dm_channel.id)
    end

    it "falls back to category name when channel name is blank" do
      blank_channel = Fabricate(:chat_channel, name: nil)

      option = load_options.find { |opt| opt[:id] == blank_channel.id }

      expect(option[:name]).to eq(blank_channel.chatable.name)
    end

    it "filters channels by the filter term" do
      expect(load_options(filter: "announce")).to contain_exactly(
        { id: other_channel.id, name: other_channel.name },
      )
    end
  end

  describe "#execute" do
    it "resolves message expressions for each input item" do
      input_items = [
        { "json" => { "text" => "First message" } },
        { "json" => { "text" => "Second message" } },
      ]
      parameters = { "channel_id" => channel.id.to_s, "message" => "={{ $json.text }}" }
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
