# frozen_string_literal: true

RSpec.describe DiscourseWorkflows::Schemas::Assignee do
  fab!(:user)
  fab!(:group)

  describe ".fields" do
    it "exposes a type discriminator with nested user and group objects" do
      fields = described_class.fields

      expect(fields[:type]).to eq(:string)
      expect(fields[:user]).to eq(type: :object, fields: DiscourseWorkflows::Schemas::User.fields)
      expect(fields[:group]).to eq(type: :object, fields: DiscourseWorkflows::Schemas::Group.fields)
    end
  end

  describe ".serialize" do
    it "returns a user-typed payload for User instances" do
      result = described_class.serialize(user)

      expect(result[:type]).to eq("user")
      expect(result[:user]).to eq(DiscourseWorkflows::Schemas::User.serialize(user))
      expect(result[:group]).to eq({})
    end

    it "returns a group-typed payload for Group instances" do
      result = described_class.serialize(group)

      expect(result[:type]).to eq("group")
      expect(result[:user]).to eq({})
      expect(result[:group]).to eq(DiscourseWorkflows::Schemas::Group.serialize(group))
    end

    it "returns an empty payload when no assignee is given" do
      expect(described_class.serialize(nil)).to eq(type: nil, user: {}, group: {})
    end
  end
end
