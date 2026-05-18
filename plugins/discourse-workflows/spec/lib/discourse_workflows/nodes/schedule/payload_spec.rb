# frozen_string_literal: true

RSpec.describe DiscourseWorkflows::Nodes::Schedule::Payload do
  describe ".build" do
    it "returns compatible timestamp fields" do
      payload = described_class.build(time: Time.utc(2026, 3, 18, 9, 0), timezone: "UTC")

      expect(payload).to include(
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

    it "formats fields in the resolved workflow timezone" do
      payload = described_class.build(time: Time.utc(2026, 3, 18, 8, 0), timezone: "Europe/Paris")

      expect(payload).to include(
        "timestamp" => "2026-03-18T09:00:00.000+01:00",
        "Hour" => "09",
        "Timezone" => "Europe/Paris (UTC+01:00)",
      )
    end
  end
end
