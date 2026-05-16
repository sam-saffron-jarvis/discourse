# frozen_string_literal: true

RSpec.describe DiscourseWorkflows::Nodes::Merge::V1 do
  def item(json)
    { "json" => json }
  end

  def json_items(items)
    items.map { |entry| { "json" => entry["json"] } }
  end

  def execute_merge(configuration:, input_1:, input_2:, input_groups: {})
    execute_node_output(
      configuration: configuration,
      input_items: input_1,
      input_groups: { "input_1" => input_1, "input_2" => input_2 }.merge(input_groups),
    ).first
  end

  it "requires fixed merge inputs but not unwired append inputs" do
    expect(described_class.input_ports("mode" => "append", "number_inputs" => 3)).to all(
      include(required: false),
    )
    expect(described_class.input_ports("mode" => "combine")).to all(include(required: true))
  end

  it "appends items from both inputs" do
    output =
      execute_merge(
        configuration: {
          "mode" => "append",
        },
        input_1: [item("a" => 1)],
        input_2: [item("b" => 2)],
        input_groups: {
          "main" => [item("a" => 1), item("b" => 2)],
        },
      )

    expect(output).to eq([item("a" => 1), item("b" => 2)])
  end

  it "appends items from indexed append inputs" do
    output =
      execute_merge(
        configuration: {
          "mode" => "append",
          "number_inputs" => 3,
        },
        input_1: [item("a" => 1)],
        input_2: [item("b" => 2)],
        input_groups: {
          "input_3" => [item("c" => 3)],
        },
      )

    expect(output).to eq([item("a" => 1), item("b" => 2), item("c" => 3)])
  end

  it "chooses a specific input branch" do
    output =
      execute_merge(
        configuration: {
          "mode" => "choose_branch",
          "use_data_of_input" => "input_2",
        },
        input_1: [item("a" => 1)],
        input_2: [item("b" => 2)],
      )

    expect(output).to eq([item("b" => 2)])
  end

  it "combines items by position" do
    output =
      execute_merge(
        configuration: {
          "mode" => "combine",
          "combine_by" => "position",
        },
        input_1: [item("id" => 1, "a" => "A")],
        input_2: [item("b" => "B")],
      )

    expect(json_items(output)).to eq([item("id" => 1, "a" => "A", "b" => "B")])
  end

  it "combines all possible item pairs" do
    output =
      execute_merge(
        configuration: {
          "mode" => "combine",
          "combine_by" => "all",
        },
        input_1: [item("a" => 1), item("a" => 2)],
        input_2: [item("b" => 3), item("b" => 4)],
      )

    expect(json_items(output)).to eq(
      [
        item("a" => 1, "b" => 3),
        item("a" => 1, "b" => 4),
        item("a" => 2, "b" => 3),
        item("a" => 2, "b" => 4),
      ],
    )
  end

  it "combines matching items by fields" do
    output =
      execute_merge(
        configuration: {
          "mode" => "combine",
          "combine_by" => "matching_fields",
          "fields_to_match" => [{ "field_1" => "id", "field_2" => "topic_id" }],
        },
        input_1: [item("id" => 1, "title" => "One"), item("id" => 2, "title" => "Two")],
        input_2: [item("topic_id" => 1, "tag" => "bug")],
      )

    expect(json_items(output)).to eq(
      [item("id" => 1, "title" => "One", "topic_id" => 1, "tag" => "bug")],
    )
    expect(output.first["pairedItem"]).to eq(
      [{ "input" => 0, "item" => 0 }, { "input" => 1, "item" => 0 }],
    )
  end
end
