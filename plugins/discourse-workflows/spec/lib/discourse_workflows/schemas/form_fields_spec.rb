# frozen_string_literal: true

RSpec.describe DiscourseWorkflows::Schemas::FormFields do
  describe ".with_keys" do
    it "uses field_name when present and falls back to a parameterized label" do
      fields =
        described_class.with_keys(
          [
            { "field_label" => "First Name", "field_type" => "text" },
            { "field_label" => "Email", "field_name" => "user_email", "field_type" => "text" },
          ],
        )

      expect(fields.map { |field| field["key"] }).to eq(%w[first_name user_email])
    end
  end

  describe ".validate_submission" do
    it "returns valid result with coerced data when all fields are valid" do
      fields = [
        { "field_label" => "Name", "field_type" => "text" },
        { "field_label" => "Age", "field_type" => "number" },
        { "field_label" => "Subscribe", "field_type" => "checkbox" },
      ]

      result =
        described_class.validate_submission(
          fields,
          { "name" => "Joffrey", "age" => "42", "subscribe" => "true" },
        )

      expect(result).to be_valid
      expect(result.errors).to be_empty
      expect(result.data).to eq("name" => "Joffrey", "age" => 42, "subscribe" => true)
    end

    it "treats values with a decimal as floats and integers otherwise" do
      result =
        described_class.validate_submission(
          [{ "field_label" => "Amount", "field_type" => "number" }],
          { "amount" => "12.5" },
        )

      expect(result).to be_valid
      expect(result.data["amount"]).to eq(12.5)
      expect(result.data["amount"]).to be_a(Float)
    end

    it "leaves blank optional number fields out without error" do
      result =
        described_class.validate_submission(
          [{ "field_label" => "Age", "field_type" => "number", "required" => false }],
          { "age" => "" },
        )

      expect(result).to be_valid
      expect(result.data["age"]).to be_nil
    end

    it "truncates long string field values" do
      result =
        described_class.validate_submission(
          [{ "field_label" => "Feedback", "field_type" => "text" }],
          { "feedback" => "a" * 10_001 },
        )

      expect(result).to be_valid
      expect(result.data["feedback"].length).to eq(described_class::MAX_FIELD_VALUE_LENGTH)
    end

    it "reports missing required fields" do
      fields = [
        { "field_label" => "Name", "field_type" => "text", "required" => true },
        { "field_label" => "Age", "field_type" => "number", "required" => true },
      ]

      result = described_class.validate_submission(fields, { "name" => "" })

      expect(result).not_to be_valid
      expect(result.errors).to contain_exactly(
        described_class::ValidationError.new(field_label: "Name", code: :missing),
        described_class::ValidationError.new(field_label: "Age", code: :missing),
      )
    end

    it "does not flag required checkboxes as missing when blank" do
      result =
        described_class.validate_submission(
          [{ "field_label" => "Agree", "field_type" => "checkbox", "required" => true }],
          { "agree" => "false" },
        )

      expect(result).to be_valid
      expect(result.data["agree"]).to be(false)
    end

    it "does not flag required checkboxes as missing when key is absent" do
      result =
        described_class.validate_submission(
          [{ "field_label" => "Agree", "field_type" => "checkbox", "required" => true }],
          {},
        )

      expect(result).to be_valid
    end

    it "reports invalid number values without raising" do
      result =
        described_class.validate_submission(
          [{ "field_label" => "Age", "field_type" => "number", "required" => true }],
          { "age" => "abc" },
        )

      expect(result).not_to be_valid
      expect(result.errors).to contain_exactly(
        described_class::ValidationError.new(field_label: "Age", code: :invalid_value),
      )
    end

    it "reports invalid number values when the input is a hash or array" do
      fields = [{ "field_label" => "Age", "field_type" => "number" }]

      [{ "age" => { "nested" => 1 } }, { "age" => [1, 2] }].each do |params|
        result = described_class.validate_submission(fields, params)
        expect(result).not_to be_valid
        expect(result.errors.first.code).to eq(:invalid_value)
      end
    end

    it "combines missing and invalid errors in one pass" do
      fields = [
        { "field_label" => "Name", "field_type" => "text", "required" => true },
        { "field_label" => "Age", "field_type" => "number", "required" => true },
      ]

      result = described_class.validate_submission(fields, { "name" => "", "age" => "abc" })

      expect(result).not_to be_valid
      expect(result.errors.map(&:code)).to contain_exactly(:missing, :invalid_value)
    end

    it "stops coercion of an invalid field but keeps coerced data for the rest" do
      fields = [
        { "field_label" => "Name", "field_type" => "text" },
        { "field_label" => "Age", "field_type" => "number" },
      ]

      result = described_class.validate_submission(fields, { "name" => "Joffrey", "age" => "abc" })

      expect(result).not_to be_valid
      expect(result.data).to eq("name" => "Joffrey")
    end

    it "uses field names as submission keys when present" do
      fields = [
        { "field_label" => "First Name", "field_type" => "text" },
        { "field_label" => "Email", "field_name" => "user_email", "field_type" => "text" },
      ]

      result =
        described_class.validate_submission(
          fields,
          { "first_name" => "Joffrey", "user_email" => "j@example.com" },
        )

      expect(result.data).to eq("first_name" => "Joffrey", "user_email" => "j@example.com")
    end

    it "tolerates empty fields" do
      result = described_class.validate_submission([], { "anything" => "value" })

      expect(result).to be_valid
      expect(result.data).to be_empty
    end

    it "tolerates nil submitted params" do
      result =
        described_class.validate_submission(
          [{ "field_label" => "Name", "field_type" => "text" }],
          nil,
        )

      expect(result).to be_valid
    end
  end
end
