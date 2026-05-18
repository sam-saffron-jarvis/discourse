# frozen_string_literal: true

RSpec.describe DiscourseWorkflows::WaitingDispatch do
  fab!(:user)
  fab!(:workflow) do
    graph =
      build_workflow_graph do |g|
        g.node "trigger-1", "trigger:manual"
        g.node "form-action-1",
               "action:form",
               name: "Waiting Form",
               configuration: {
                 "form_title" => "Waiting form",
                 "form_fields" => [
                   { "field_label" => "Feedback", "field_type" => "text", "required" => true },
                 ],
               }
        g.chain "trigger-1", "form-action-1"
      end
    Fabricate(:discourse_workflows_workflow, published: true, **graph)
  end

  let(:resume_token) { SecureRandom.uuid }
  let(:guardian) { Guardian.new(user) }

  before { allow(MessageBus).to receive(:publish) }

  let!(:execution) do
    exec = DiscourseWorkflows::Executor.new(workflow, "trigger-1", {}).run
    exec.update!(resume_token: resume_token)
    exec
  end
  let(:signature) do
    DiscourseWorkflows::WaitingExecution.resume_signature(
      execution_id: execution.id,
      resume_token: resume_token,
    )
  end

  def dispatch(http_method:, path: "", params: {}, signature: self.signature)
    described_class.call(
      execution_id: execution.id,
      signature: signature,
      http_method: http_method,
      path: path,
      node_type: "form",
      params: params,
      service_params: {
        guardian: guardian,
      },
    )
  end

  describe ".call" do
    it "serves waiting form status through the node webhook descriptor" do
      result = dispatch(http_method: "GET", path: "status")

      expect(result.status).to eq(:ok)
      expect(result.body).to eq(status: "form_waiting")
    end

    it "serves waiting form data through the node webhook descriptor" do
      result = dispatch(http_method: "GET")

      expect(result.status).to eq(:ok)
      expect(result.body[:form_title]).to eq("Waiting form")
      expect(result.body[:form_fields].first["key"]).to eq("feedback")
      expect(result.body[:form_waiting_url]).to be_present
      expect(result.body[:form_submit_url]).to be_present
      expect(result.body[:form_status_url]).to be_present
      expect(result.body.to_json).not_to include(resume_token)
    end

    it "returns structured validation errors from the waiting form handler" do
      result = dispatch(http_method: "POST", params: { form_data: {} })

      expect(result.status).to eq(:unprocessable_entity)
      expect(result.body[:errors]).to contain_exactly(field_label: "Feedback", code: :missing)
    end

    it "resumes the execution through the waiting form handler" do
      result = dispatch(http_method: "POST", params: { form_data: { "feedback" => "Approved" } })

      expect(result.status).to eq(:ok)
      expect(result.body[:status]).to eq("success")
      expect(execution.reload.status).to eq("success")
    end

    it "returns not_found when the signature does not match" do
      result = dispatch(http_method: "GET", signature: "invalid")

      expect(result.status).to eq(:not_found)
      expect(result.body).to eq(error: "not_found")
    end

    it "returns not_found for paths the waiting node did not declare" do
      result = dispatch(http_method: "GET", path: "unknown")

      expect(result.status).to eq(:not_found)
      expect(result.body).to eq(error: "not_found")
    end
  end

  describe ".waiting_for?" do
    it "detects waiting executions handled by form restart webhooks" do
      expect(described_class.waiting_for?(execution, node_type: "form")).to eq(true)

      dispatch(http_method: "POST", params: { form_data: { "feedback" => "Approved" } })

      expect(described_class.waiting_for?(execution.reload, node_type: "form")).to eq(false)
    end
  end
end
