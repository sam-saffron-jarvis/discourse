# frozen_string_literal: true

RSpec.describe DiscourseWorkflows::Nodes::Schedule::V1 do
  describe ".validate_configuration" do
    it "accepts valid rules" do
      config = { "rule" => { "interval" => [{ "field" => "minutes", "minutesInterval" => 5 }] } }
      errors = ActiveModel::Errors.new(Object.new)
      described_class.validate_configuration(config, errors)
      expect(errors).to be_empty
    end

    it "accepts valid cron rules" do
      config = {
        "rule" => {
          "interval" => [{ "field" => "cronExpression", "expression" => "0 9 * * *" }],
        },
      }
      errors = ActiveModel::Errors.new(Object.new)
      described_class.validate_configuration(config, errors)
      expect(errors).to be_empty
    end

    it "rejects empty rules" do
      config = { "rule" => { "interval" => [] } }
      errors = ActiveModel::Errors.new(Object.new)
      described_class.validate_configuration(config, errors)
      expect(errors).not_to be_empty
    end

    it "rejects invalid cron rules" do
      config = {
        "rule" => {
          "interval" => [{ "field" => "cronExpression", "expression" => "invalid" }],
        },
      }
      errors = ActiveModel::Errors.new(Object.new)
      described_class.validate_configuration(config, errors)
      expect(errors).not_to be_empty
    end

    it "accepts multiple rules" do
      config = {
        "rule" => {
          "interval" => Array.new(8) { { "field" => "minutes", "minutesInterval" => 5 } },
        },
      }
      errors = ActiveModel::Errors.new(Object.new)
      described_class.validate_configuration(config, errors)
      expect(errors).to be_empty
    end

    it "rejects seconds rules" do
      config = { "rule" => { "interval" => [{ "field" => "seconds", "secondsInterval" => 30 }] } }
      errors = ActiveModel::Errors.new(Object.new)
      described_class.validate_configuration(config, errors)
      expect(errors).not_to be_empty
    end
  end

  describe "#output" do
    it "returns compatible timestamp fields" do
      freeze_time Time.utc(2026, 3, 18, 9, 0)
      trigger = described_class.new
      output = trigger.output
      expect(output).to include(
        "timestamp" => "2026-03-18T09:00:00.000Z",
        "Readable date" => "March 18th 2026, 9:00:00 am",
        "Readable time" => "9:00:00 am",
        "Day of week" => "Wednesday",
        "Year" => "2026",
        "Month" => "March",
        "Day of month" => "18",
        "Hour" => "09",
        "Minute" => "00",
        "Second" => "00",
        "Timezone" => "UTC (UTC+00:00)",
      )
    end

    it "uses the requested timezone" do
      trigger = described_class.new
      output = trigger.output(time: Time.utc(2026, 3, 18, 8, 0), timezone: "Europe/Paris")

      expect(output).to include(
        "timestamp" => "2026-03-18T09:00:00.000+01:00",
        "Hour" => "09",
        "Timezone" => "Europe/Paris (UTC+01:00)",
      )
    end
  end
end
