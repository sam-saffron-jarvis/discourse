# frozen_string_literal: true

RSpec.describe DiscourseWorkflows::ScheduleRule do
  fab!(:user)
  fab!(:workflow) { Fabricate(:discourse_workflows_workflow, created_by: user) }

  describe ".to_cron_expression" do
    let(:node_key) { "workflow-1:trigger-1" }

    it "converts seconds interval" do
      rule = { "interval" => "seconds", "seconds_between_triggers" => 30 }
      expect(described_class.to_cron_expression(rule, node_key)).to eq("*/30 * * * * *")
    end

    it "converts minutes interval" do
      rule = { "interval" => "minutes", "minutes_between_triggers" => 5 }
      expect(described_class.to_cron_expression(rule, node_key)).to eq("46 */5 * * * *")
    end

    it "converts hours interval with trigger_at_minute" do
      rule = { "interval" => "hours", "hours_between_triggers" => 2, "trigger_at_minute" => 15 }
      expect(described_class.to_cron_expression(rule, node_key)).to eq("46 15 */2 * * *")
    end

    it "converts non-divisor hours interval to hourly cron for recurrence filtering" do
      rule = { "interval" => "hours", "hours_between_triggers" => 18, "trigger_at_minute" => 15 }
      expect(described_class.to_cron_expression(rule, node_key)).to eq("46 15 * * * *")
    end

    it "converts days interval" do
      rule = {
        "interval" => "days",
        "days_between_triggers" => 1,
        "trigger_at_hour" => 9,
        "trigger_at_minute" => 30,
      }
      expect(described_class.to_cron_expression(rule, node_key)).to eq("46 30 9 * * *")
    end

    it "converts weeks interval with weekdays" do
      rule = {
        "interval" => "weeks",
        "weeks_between_triggers" => 1,
        "trigger_on_weekdays" => [1, 5],
        "trigger_at_hour" => 8,
        "trigger_at_minute" => 0,
      }
      expect(described_class.to_cron_expression(rule, node_key)).to eq("46 0 8 * * 1,5")
    end

    it "uses wildcard weekdays when weekdays are empty" do
      rule = { "interval" => "weeks", "trigger_on_weekdays" => [] }
      expect(described_class.to_cron_expression(rule, node_key)).to eq("46 4 2 * * *")
    end

    it "converts months interval" do
      rule = {
        "interval" => "months",
        "months_between_triggers" => 3,
        "trigger_at_day_of_month" => 15,
        "trigger_at_hour" => 12,
        "trigger_at_minute" => 0,
      }
      expect(described_class.to_cron_expression(rule, node_key)).to eq("46 0 12 15 */3 *")
    end

    it "applies deterministic cron jitter to omitted time fields" do
      rule = { "interval" => "months", "months_between_triggers" => 1 }
      expect(described_class.to_cron_expression(rule, node_key)).to eq("46 4 2 27 */1 *")
    end

    it "clamps cron generation values to valid ranges" do
      rule = { "interval" => "minutes", "minutes_between_triggers" => 100 }
      expect(described_class.to_cron_expression(rule, node_key)).to eq("46 */59 * * * *")
    end
  end

  describe ".matches_now?" do
    let(:dtstart) { Time.utc(2026, 1, 1, 0, 0) }

    it "matches seconds interval within the current minute" do
      freeze_time Time.utc(2026, 3, 18, 9, 0)
      rule = { "interval" => "seconds", "seconds_between_triggers" => 30 }
      expect(described_class.matches_now?(rule, dtstart, Time.current.utc)).to be(true)
    end

    it "matches cron rules via CronParser" do
      freeze_time Time.utc(2026, 3, 18, 9, 0)
      rule = { "interval" => "cron", "cron" => "0 9 * * *" }
      expect(described_class.matches_now?(rule, dtstart, Time.current.utc)).to be(true)
    end

    it "does not match cron at wrong time" do
      freeze_time Time.utc(2026, 3, 18, 10, 0)
      rule = { "interval" => "cron", "cron" => "0 9 * * *" }
      expect(described_class.matches_now?(rule, dtstart, Time.current.utc)).to be(false)
    end

    it "matches minutes interval" do
      freeze_time Time.utc(2026, 3, 18, 9, 10)
      rule = { "interval" => "minutes", "minutes_between_triggers" => 5 }
      expect(described_class.matches_now?(rule, dtstart, Time.current.utc)).to be(true)
    end

    it "does not match minutes at wrong time" do
      freeze_time Time.utc(2026, 3, 18, 9, 11)
      rule = { "interval" => "minutes", "minutes_between_triggers" => 5 }
      expect(described_class.matches_now?(rule, dtstart, Time.current.utc)).to be(false)
    end

    it "matches hours interval at correct minute" do
      freeze_time Time.utc(2026, 3, 18, 10, 30)
      rule = { "interval" => "hours", "hours_between_triggers" => 2, "trigger_at_minute" => 30 }
      expect(described_class.matches_now?(rule, dtstart, Time.current.utc)).to be(true)
    end

    it "matches daily interval" do
      freeze_time Time.utc(2026, 3, 18, 9, 0)
      rule = {
        "interval" => "days",
        "days_between_triggers" => 1,
        "trigger_at_hour" => 9,
        "trigger_at_minute" => 0,
      }
      expect(described_class.matches_now?(rule, dtstart, Time.current.utc)).to be(true)
    end

    it "matches weekly on correct weekday" do
      freeze_time Time.utc(2026, 3, 16, 8, 0) # Monday
      rule = {
        "interval" => "weeks",
        "weeks_between_triggers" => 1,
        "trigger_on_weekdays" => [1],
        "trigger_at_hour" => 8,
        "trigger_at_minute" => 0,
      }
      expect(described_class.matches_now?(rule, dtstart, Time.current.utc)).to be(true)
    end

    it "does not match weekly on wrong weekday" do
      freeze_time Time.utc(2026, 3, 17, 8, 0) # Tuesday
      rule = {
        "interval" => "weeks",
        "weeks_between_triggers" => 1,
        "trigger_on_weekdays" => [1],
        "trigger_at_hour" => 8,
        "trigger_at_minute" => 0,
      }
      expect(described_class.matches_now?(rule, dtstart, Time.current.utc)).to be(false)
    end

    it "matches monthly on correct day" do
      freeze_time Time.utc(2026, 3, 15, 12, 0)
      rule = {
        "interval" => "months",
        "months_between_triggers" => 1,
        "trigger_at_day_of_month" => 15,
        "trigger_at_hour" => 12,
        "trigger_at_minute" => 0,
      }
      expect(described_class.matches_now?(rule, dtstart, Time.current.utc)).to be(true)
    end

    it "matches in the configured timezone" do
      freeze_time Time.utc(2026, 3, 18, 8, 0)
      rule = {
        "interval" => "days",
        "days_between_triggers" => 1,
        "trigger_at_hour" => 9,
        "trigger_at_minute" => 0,
      }

      expect(
        described_class.matches_now?(rule, dtstart, Time.current.utc, timezone: "Europe/Paris"),
      ).to be(true)
    end
  end

  describe ".rules_from_configuration" do
    it "returns rules array" do
      config = { "rules" => [{ "interval" => "days" }] }
      expect(described_class.rules_from_configuration(config)).to eq([{ "interval" => "days" }])
    end

    it "accepts imported schedule trigger rule shape" do
      config = {
        "rule" => {
          "interval" => [
            { "field" => "cronExpression", "expression" => "0 9 * * MON-FRI" },
            {
              "field" => "days",
              "daysInterval" => 3,
              "triggerAtHour" => 9,
              "triggerAtMinute" => 30,
            },
          ],
        },
      }

      expect(described_class.rules_from_configuration(config)).to eq(
        [
          { "interval" => "cronExpression", "cron" => "0 9 * * MON-FRI" },
          {
            "interval" => "days",
            "days_between_triggers" => 3,
            "trigger_at_hour" => 9,
            "trigger_at_minute" => 30,
          },
        ],
      )
    end

    it "returns empty array for empty config" do
      expect(described_class.rules_from_configuration({})).to eq([])
    end
  end

  describe ".valid_rule?" do
    it "validates cron rules" do
      expect(described_class.valid_rule?({ "interval" => "cron", "cron" => "0 9 * * *" })).to eq(
        true,
      )
    end

    it "validates imported cronExpression rules" do
      expect(
        described_class.valid_rule?(
          { "field" => "cronExpression", "expression" => "0 9 * * MON-FRI" },
        ),
      ).to eq(true)
    end

    it "rejects invalid cron" do
      expect(described_class.valid_rule?({ "interval" => "cron", "cron" => "invalid" })).to eq(
        false,
      )
    end

    it "accepts interval rules with valid fields" do
      expect(
        described_class.valid_rule?({ "interval" => "minutes", "minutes_between_triggers" => 5 }),
      ).to be(true)
      expect(
        described_class.valid_rule?(
          { "interval" => "hours", "hours_between_triggers" => 2, "trigger_at_minute" => 30 },
        ),
      ).to be(true)
      expect(
        described_class.valid_rule?(
          {
            "interval" => "days",
            "days_between_triggers" => 3,
            "trigger_at_hour" => 9,
            "trigger_at_minute" => 0,
          },
        ),
      ).to be(true)
      expect(
        described_class.valid_rule?(
          {
            "interval" => "weeks",
            "weeks_between_triggers" => 2,
            "trigger_on_weekdays" => [1, 3],
            "trigger_at_hour" => 8,
            "trigger_at_minute" => 0,
          },
        ),
      ).to be(true)
      expect(
        described_class.valid_rule?(
          {
            "interval" => "months",
            "months_between_triggers" => 3,
            "trigger_at_day_of_month" => 15,
            "trigger_at_hour" => 9,
            "trigger_at_minute" => 0,
          },
        ),
      ).to be(true)
    end

    it "accepts interval rules with omitted optional fields" do
      %w[minutes hours days weeks months].each do |interval|
        expect(described_class.valid_rule?({ "interval" => interval })).to be(true)
      end
    end

    it "rejects interval fields out of range" do
      expect(
        described_class.valid_rule?({ "interval" => "minutes", "minutes_between_triggers" => 0 }),
      ).to be(false)
      expect(
        described_class.valid_rule?({ "interval" => "minutes", "minutes_between_triggers" => 60 }),
      ).to be(false)

      expect(
        described_class.valid_rule?({ "interval" => "hours", "hours_between_triggers" => 0 }),
      ).to be(false)
      expect(
        described_class.valid_rule?({ "interval" => "hours", "hours_between_triggers" => 24 }),
      ).to be(false)
      expect(
        described_class.valid_rule?({ "interval" => "hours", "trigger_at_minute" => 60 }),
      ).to be(false)

      expect(
        described_class.valid_rule?({ "interval" => "days", "days_between_triggers" => 0 }),
      ).to be(false)
      expect(
        described_class.valid_rule?({ "interval" => "days", "days_between_triggers" => 32 }),
      ).to be(false)
      expect(described_class.valid_rule?({ "interval" => "days", "trigger_at_hour" => 24 })).to be(
        false,
      )
      expect(
        described_class.valid_rule?({ "interval" => "days", "trigger_at_minute" => 60 }),
      ).to be(false)

      expect(
        described_class.valid_rule?({ "interval" => "weeks", "weeks_between_triggers" => 0 }),
      ).to be(false)
      expect(
        described_class.valid_rule?({ "interval" => "weeks", "weeks_between_triggers" => 53 }),
      ).to be(false)
      expect(
        described_class.valid_rule?({ "interval" => "weeks", "trigger_on_weekdays" => [0, 7] }),
      ).to be(false)

      expect(
        described_class.valid_rule?({ "interval" => "months", "months_between_triggers" => 0 }),
      ).to be(false)
      expect(
        described_class.valid_rule?({ "interval" => "months", "months_between_triggers" => 13 }),
      ).to be(false)
      expect(
        described_class.valid_rule?({ "interval" => "months", "trigger_at_day_of_month" => 0 }),
      ).to be(false)
      expect(
        described_class.valid_rule?({ "interval" => "months", "trigger_at_day_of_month" => 32 }),
      ).to be(false)
    end

    it "validates seconds rules" do
      expect(
        described_class.valid_rule?({ "interval" => "seconds", "seconds_between_triggers" => 30 }),
      ).to be(true)
    end

    it "rejects seconds out of range" do
      expect(
        described_class.valid_rule?({ "interval" => "seconds", "seconds_between_triggers" => 0 }),
      ).to be(false)
      expect(
        described_class.valid_rule?({ "interval" => "seconds", "seconds_between_triggers" => 60 }),
      ).to be(false)
    end

    it "rejects unknown intervals" do
      expect(described_class.valid_rule?({ "interval" => "unknown" })).to be(false)
    end
  end

  describe ".fire_matching_trigger!" do
    fab!(:schedule_workflow, :discourse_workflows_workflow) do
      graph =
        build_workflow_graph do |g|
          g.node "trigger-1",
                 "trigger:schedule",
                 configuration: {
                   "rules" => [{ "interval" => "cron", "cron" => "0 9 * * *" }],
                 }
        end
      Fabricate(:discourse_workflows_workflow, published: true, created_by: user, **graph)
    end

    let(:workflow_version) { schedule_workflow.published_version }
    let(:node) { workflow_version.nodes.first }
    let(:published_trigger) do
      DiscourseWorkflows::PublishedTrigger.new(
        workflow: schedule_workflow,
        workflow_version: workflow_version,
        trigger_node: node,
      )
    end

    it "enqueues a workflow execution job when a rule matches" do
      freeze_time Time.utc(2026, 3, 18, 9, 0)

      expect {
        described_class.fire_matching_trigger!(published_trigger, Time.current.utc)
      }.to change { Jobs::DiscourseWorkflows::ExecuteWorkflow.jobs.size }.by(1)

      job = Jobs::DiscourseWorkflows::ExecuteWorkflow.jobs.last
      expect(job["args"].first["workflow_id"]).to eq(schedule_workflow.id)
      expect(job["args"].first["workflow_version_id"]).to eq(workflow_version.id)
      expect(job["args"].first["trigger_node_id"]).to eq("trigger-1")
    end

    it "does not enqueue when no rule matches" do
      freeze_time Time.utc(2026, 3, 18, 10, 0)

      expect {
        described_class.fire_matching_trigger!(published_trigger, Time.current.utc)
      }.not_to change { Jobs::DiscourseWorkflows::ExecuteWorkflow.jobs.size }
    end

    it "does not fire twice in the same minute" do
      freeze_time Time.utc(2026, 3, 18, 9, 0)
      now = Time.current.utc

      described_class.fire_matching_trigger!(published_trigger, now)
      expect(Jobs::DiscourseWorkflows::ExecuteWorkflow.jobs.size).to eq(1)

      described_class.fire_matching_trigger!(published_trigger, now)
      expect(Jobs::DiscourseWorkflows::ExecuteWorkflow.jobs.size).to eq(1)
    end

    it "fires each matching second for six-field cron rules" do
      freeze_time Time.utc(2026, 3, 18, 9, 0)
      cron_node = {
        "id" => "trigger-2",
        "parameters" => {
          "rules" => [{ "interval" => "cron", "cron" => "*/20 * * * * *" }],
        },
      }
      cron_match =
        DiscourseWorkflows::PublishedTrigger.new(
          workflow: schedule_workflow,
          workflow_version: workflow_version,
          trigger_node: cron_node,
        )

      expect { described_class.fire_matching_trigger!(cron_match, Time.current.utc) }.to change {
        Jobs::DiscourseWorkflows::ExecuteWorkflow.jobs.size
      }.by(3)

      timestamps =
        Jobs::DiscourseWorkflows::ExecuteWorkflow
          .jobs
          .last(3)
          .map { |job| job["args"].first.dig("trigger_data", "timestamp") }
      expect(timestamps).to eq(
        %w[2026-03-18T09:00:00.000Z 2026-03-18T09:00:20.000Z 2026-03-18T09:00:40.000Z],
      )
    end

    it "fires independent rules that match the same second" do
      freeze_time Time.utc(2026, 3, 18, 9, 0)
      cron_node = {
        "id" => "trigger-2",
        "parameters" => {
          "rules" => [
            { "interval" => "cron", "cron" => "0 9 * * *" },
            { "interval" => "cron", "cron" => "0 9 * * *" },
          ],
        },
      }
      cron_match =
        DiscourseWorkflows::PublishedTrigger.new(
          workflow: schedule_workflow,
          workflow_version: workflow_version,
          trigger_node: cron_node,
        )

      expect { described_class.fire_matching_trigger!(cron_match, Time.current.utc) }.to change {
        Jobs::DiscourseWorkflows::ExecuteWorkflow.jobs.size
      }.by(2)
    end

    it "skips seconds rules" do
      freeze_time Time.utc(2026, 3, 18, 9, 0)
      seconds_node = {
        "id" => "trigger-2",
        "parameters" => {
          "rules" => [{ "interval" => "seconds", "seconds_between_triggers" => 10 }],
        },
      }

      seconds_match =
        DiscourseWorkflows::PublishedTrigger.new(
          workflow: schedule_workflow,
          workflow_version: workflow_version,
          trigger_node: seconds_node,
        )

      expect {
        described_class.fire_matching_trigger!(seconds_match, Time.current.utc)
      }.not_to change { Jobs::DiscourseWorkflows::ExecuteWorkflow.jobs.size }
    end
  end

  describe ".restart_stalled_chains!" do
    fab!(:seconds_workflow, :discourse_workflows_workflow) do
      graph =
        build_workflow_graph do |g|
          g.node "trigger-1",
                 "trigger:schedule",
                 configuration: {
                   "rules" => [{ "interval" => "seconds", "seconds_between_triggers" => 10 }],
                 }
        end
      Fabricate(:discourse_workflows_workflow, published: true, created_by: user, **graph)
    end

    let(:workflow_version) { seconds_workflow.published_version }
    let(:node) { workflow_version.nodes.first }
    let(:published_trigger) do
      DiscourseWorkflows::PublishedTrigger.new(
        workflow: seconds_workflow,
        workflow_version: workflow_version,
        trigger_node: node,
      )
    end

    it "starts a seconds chain when no recent trigger exists" do
      freeze_time Time.utc(2026, 3, 18, 9, 0)

      described_class.restart_stalled_chains!(published_trigger, Time.current.utc)
      expect(Jobs::DiscourseWorkflows::ExecuteSecondsSchedule.jobs.size).to eq(1)
    end

    it "does not restart a chain when trigger fired recently" do
      freeze_time Time.utc(2026, 3, 18, 9, 0)

      described_class.mark_seconds_triggered!(seconds_workflow, "trigger-1", 0, Time.current.utc)
      described_class.restart_stalled_chains!(published_trigger, Time.current.utc)
      expect(Jobs::DiscourseWorkflows::ExecuteSecondsSchedule.jobs.size).to eq(0)
    end

    it "skips non-seconds rules" do
      freeze_time Time.utc(2026, 3, 18, 9, 0)
      cron_node = {
        "id" => "trigger-2",
        "parameters" => {
          "rules" => [{ "interval" => "cron", "cron" => "0 9 * * *" }],
        },
      }

      cron_match =
        DiscourseWorkflows::PublishedTrigger.new(
          workflow: seconds_workflow,
          workflow_version: workflow_version,
          trigger_node: cron_node,
        )

      described_class.restart_stalled_chains!(cron_match, Time.current.utc)
      expect(Jobs::DiscourseWorkflows::ExecuteSecondsSchedule.jobs.size).to eq(0)
    end
  end

  describe ".start_seconds_chain!" do
    it "stores a token and enqueues a job" do
      rule = { "interval" => "seconds", "seconds_between_triggers" => 10 }
      published_trigger =
        DiscourseWorkflows::PublishedTrigger.new(
          workflow: workflow,
          workflow_version: workflow.draft_version,
          trigger_node: {
            "id" => "trigger-1",
          },
        )
      described_class.start_seconds_chain!(published_trigger, 0, rule)

      data = workflow.reload.node_static_data("trigger-1")
      expect(data.dig("seconds_tokens", "0")).to be_present
    end
  end

  describe ".seconds_interval" do
    it "clamps to the valid range" do
      expect(
        described_class.seconds_interval(
          { "interval" => "seconds", "seconds_between_triggers" => 0 },
        ),
      ).to eq(1)
      expect(
        described_class.seconds_interval(
          { "interval" => "seconds", "seconds_between_triggers" => 600 },
        ),
      ).to eq(59)
    end

    it "passes through valid values" do
      rule = { "interval" => "seconds", "seconds_between_triggers" => 30 }
      expect(described_class.seconds_interval(rule)).to eq(30)
    end
  end

  describe ".seconds_token_valid?" do
    it "returns true for matching token" do
      rule = { "interval" => "seconds", "seconds_between_triggers" => 10 }
      published_trigger =
        DiscourseWorkflows::PublishedTrigger.new(
          workflow: workflow,
          workflow_version: workflow.draft_version,
          trigger_node: {
            "id" => "trigger-1",
          },
        )
      described_class.start_seconds_chain!(published_trigger, 0, rule)
      token = workflow.reload.node_static_data("trigger-1").dig("seconds_tokens", "0")

      expect(described_class.seconds_token_valid?(workflow, "trigger-1", 0, token)).to be(true)
    end

    it "returns false for stale token" do
      expect(described_class.seconds_token_valid?(workflow, "trigger-1", 0, "old-token")).to eq(
        false,
      )
    end
  end
end
