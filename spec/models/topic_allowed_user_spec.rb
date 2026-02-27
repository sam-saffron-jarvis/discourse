# frozen_string_literal: true

RSpec.describe TopicAllowedUser do
  it { is_expected.to belong_to :user }
  it { is_expected.to belong_to :topic }

  describe "cleanup_inaccessible_notifications" do
    it "enqueues DeleteInaccessibleNotifications when destroyed" do
      pm = Fabricate(:private_message_topic)
      tau = pm.topic_allowed_users.first

      tau.destroy!

      expect_job_enqueued(job: :delete_inaccessible_notifications, args: { topic_id: pm.id })
    end
  end
end
