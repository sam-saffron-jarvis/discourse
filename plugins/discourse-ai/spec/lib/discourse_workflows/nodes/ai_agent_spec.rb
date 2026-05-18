# frozen_string_literal: true

RSpec.describe DiscourseWorkflows::Nodes::AiAgent::V1 do
  fab!(:agent) { Fabricate(:ai_agent, name: "Workflow agent", enabled: true) }

  let(:bot) { instance_double(DiscourseAi::Agents::Bot) }
  let(:prompts) { [] }

  before do
    SiteSetting.discourse_ai_enabled = true

    allow(DiscourseAi::Agents::Bot).to receive(:as).and_return(bot)
    allow(bot).to receive(:reply) do |bot_context, &block|
      prompt = bot_context.messages.first[:content]

      prompts << prompt
      block.call("Reply to #{prompt}", nil, nil)
    end
  end

  it "runs the agent once per input item with item-specific parameters" do
    items =
      execute_node_output(
        configuration: {
          "agent_id" => agent.id,
          "prompt" => "={{ 'Prompt ' + $json.name }}",
        },
        input_items: [{ "json" => { "name" => "Ada" } }, { "json" => { "name" => "Grace" } }],
      ).first

    expect(prompts).to eq(["Prompt Ada", "Prompt Grace"])
    expect(items.map { |item| item["json"]["result"] }).to eq(
      ["Reply to Prompt Ada", "Reply to Prompt Grace"],
    )
    expect(items.map { |item| item["pairedItem"] }).to eq([{ "item" => 0 }, { "item" => 1 }])
    expect(bot).to have_received(:reply).twice
  end
end
