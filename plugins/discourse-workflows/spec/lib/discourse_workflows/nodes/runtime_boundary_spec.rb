# frozen_string_literal: true

RSpec.describe DiscourseWorkflows::NodeType do
  it "keeps node implementations on public execution and webhook contexts" do
    forbidden_patterns = [
      /\bWaitingExecution\b/,
      /\bWaitingWebhookRunner\b/,
      /\bExecutor\.resume\b/,
      /\bExecution\.claim_for_resume\b/,
      /\bForm::Show\b/,
      /\bForm::Resume\b/,
      /\bFormCompletion\b/,
      /\bFormPayload\b/,
    ]
    node_files =
      Dir[
        File.join(Rails.root, "plugins/discourse-workflows/lib/discourse_workflows/nodes/**/*.rb")
      ]

    violations =
      node_files.flat_map do |path|
        File
          .readlines(path)
          .filter_map
          .with_index(1) do |line, line_number|
            next unless forbidden_patterns.any? { |pattern| line.match?(pattern) }

            "#{path}:#{line_number}: #{line.strip}"
          end
      end

    expect(violations).to be_empty
  end
end
