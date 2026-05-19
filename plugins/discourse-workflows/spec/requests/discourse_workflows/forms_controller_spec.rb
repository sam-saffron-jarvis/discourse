# frozen_string_literal: true

RSpec.describe DiscourseWorkflows::FormsController do
  fab!(:workflow) do
    graph =
      build_workflow_graph do |g|
        g.node "trigger-1",
               "trigger:form",
               configuration: {
                 "uuid" => "a1b2c3d4-e5f6-7890-abcd-ef0123456789",
                 "form_title" => "Test Form",
                 "form_fields" => [
                   { "field_label" => "Name", "field_type" => "text", "required" => true },
                 ],
                 "response_mode" => "on_received",
               }
      end
    Fabricate(:discourse_workflows_workflow, published: true, **graph)
  end

  let(:form_uuid) { workflow.nodes.find { |n| n["type"] == "trigger:form" }["webhook_id"] }
  let(:form_path) { "/workflows/form/#{form_uuid}.json" }

  let(:origin_headers) { { "Origin" => "http://#{Discourse.current_hostname}" } }
  let(:initial_resume_token) do
    get form_path
    expect(response).to have_http_status(:ok)
    response.parsed_body["resume_token"]
  end

  describe "GET /workflows/form/:uuid.json" do
    it "returns form schema" do
      expect { get form_path }.not_to change { DiscourseWorkflows::Execution.count }

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["form_title"]).to eq("Test Form")
      expect(json["fields"].length).to eq(1)
      expect(json["fields"].first["name"]).to eq("name")
      expect(json["data"]).to eq("name" => "")
      expect(json["form_submit_url"]).to eq(form_path)
      expect(json).not_to have_key("form_fields")
      expect(json["resume_token"]).to be_present
    end

    it "returns 404 for unknown uuid" do
      get "/workflows/form/00000000-0000-0000-0000-000000000000.json"
      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 for unpublished workflow" do
      unpublish_workflow!(workflow)
      get form_path
      expect(response).to have_http_status(:not_found)
    end

    it "rate limits repeated show requests" do
      RateLimiter.any_instance.expects(:performed!).raises(RateLimiter::LimitExceeded.new(60))

      get form_path

      expect(response).to have_http_status(:too_many_requests)
    end

    context "when the form requires a logged-in user" do
      fab!(:user)

      before do
        trigger_node = workflow.nodes.find { |n| n["type"] == "trigger:form" }
        trigger_node["parameters"]["authentication"] = "login_required"
        workflow.update!(nodes: workflow.nodes)
        publish_workflow!(workflow)
      end

      it "returns 403 for anonymous users" do
        get form_path
        expect(response).to have_http_status(:forbidden)
      end

      it "returns form schema for logged-in users" do
        sign_in(user)
        get form_path
        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe "POST /workflows/form/:uuid.json" do
    it "executes workflow without returning a raw waiting token" do
      post form_path,
           params: {
             resume_token: initial_resume_token,
             form_data: {
               name: "Test User",
             },
           },
           headers: origin_headers
      expect(response).to have_http_status(:ok)

      json = response.parsed_body
      expect(json).not_to have_key("resume_token")

      execution = DiscourseWorkflows::Execution.last
      expect(execution.trigger_node_id).to eq("trigger-1")
      expect(execution.execution_data.context_data["__resume_token"]).to be_present
    end

    it "stores initial URL query parameters in the trigger payload" do
      get form_path, params: { source: "email", ref: "spring" }
      expect(response).to have_http_status(:ok)

      post form_path,
           params: {
             resume_token: response.parsed_body["resume_token"],
             form_data: {
               name: "Test User",
             },
           },
           headers: origin_headers

      execution = DiscourseWorkflows::Execution.last
      expect(execution.trigger_data).to include(
        "name" => "Test User",
        "formMode" => "production",
        "formQueryParameters" => {
          "source" => "email",
          "ref" => "spring",
        },
      )
      expect(execution.trigger_data).not_to have_key("form_data")
    end

    context "when response mode waits for the workflow to finish" do
      before do
        update_workflow_node(workflow, "trigger-1") do |node|
          node["parameters"]["response_mode"] = "workflow_finishes"
        end
        publish_workflow!(workflow)
      end

      it "returns no response body after a successful execution without Form Ending output" do
        post form_path,
             params: {
               resume_token: initial_resume_token,
               form_data: {
                 name: "Test User",
               },
             },
             headers: origin_headers
        expect(response).to have_http_status(:ok)
        expect(response.body).to be_blank
      end

      it "returns an error response when the workflow fails" do
        extra =
          build_workflow_graph do |g|
            g.node "wait-1",
                   "flow:wait",
                   configuration: {
                     "resume" => "time_interval",
                     "wait_amount" => 0,
                     "wait_unit" => "seconds",
                   }
          end
        workflow.update!(
          nodes: workflow.nodes + extra[:nodes],
          connections: [
            {
              "source_node_id" => "trigger-1",
              "target_node_id" => "wait-1",
              "source_output_index" => 0,
              "target_input_index" => 0,
            },
          ],
        )
        publish_workflow!(workflow)

        post form_path,
             params: {
               resume_token: initial_resume_token,
               form_data: {
                 name: "Test User",
               },
             },
             headers: origin_headers
        expect(response).to have_http_status(:internal_server_error)
        expect(response.parsed_body).to include(
          "response_mode" => "workflow_finishes",
          "status" => "error",
          "errors" => [I18n.t("discourse_workflows.errors.workflow_failed")],
        )
        expect(response.parsed_body).not_to have_key("error")
        expect(DiscourseWorkflows::Execution.last).to have_attributes(status: "error")
      end

      it "returns no response body for non-form waits" do
        extra =
          build_workflow_graph do |g|
            g.node "wait-1",
                   "flow:wait",
                   configuration: {
                     "resume" => "time_interval",
                     "wait_amount" => 1,
                     "wait_unit" => "hours",
                   }
          end
        workflow.update!(
          nodes: workflow.nodes + extra[:nodes],
          connections: [
            {
              "source_node_id" => "trigger-1",
              "target_node_id" => "wait-1",
              "source_output_index" => 0,
              "target_input_index" => 0,
            },
          ],
        )
        publish_workflow!(workflow)

        post form_path,
             params: {
               resume_token: initial_resume_token,
               form_data: {
                 name: "Test User",
               },
             },
             headers: origin_headers
        expect(response).to have_http_status(:ok)
        expect(response.body).to be_blank
        expect(DiscourseWorkflows::Execution.last).to have_attributes(status: "waiting")
      end
    end

    it "returns 422 when the initial submission token is missing" do
      post form_path, params: { form_data: { name: "Test User" } }, headers: origin_headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to include(
        "errors" => [I18n.t("discourse_workflows.errors.invalid_form_token")],
      )
      expect(response.parsed_body).not_to have_key("error")
    end

    it "returns 422 with structured errors when required fields are omitted" do
      post form_path,
           params: {
             resume_token: initial_resume_token,
             form_data: {
             },
           },
           headers: origin_headers
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["errors"]).to eq(
        [{ "field_label" => "Name", "code" => "missing" }],
      )
      expect(response.parsed_body).not_to have_key("error")
    end

    context "when the form requires a logged-in user" do
      fab!(:user)

      before do
        trigger_node = workflow.nodes.find { |n| n["type"] == "trigger:form" }
        trigger_node["parameters"]["authentication"] = "login_required"
        workflow.update!(nodes: workflow.nodes)
        publish_workflow!(workflow)
      end

      it "returns 403 for anonymous users" do
        post form_path, params: { form_data: { name: "Test User" } }, headers: origin_headers
        expect(response).to have_http_status(:forbidden)
      end

      it "executes workflow for logged-in users" do
        sign_in(user)
        post form_path,
             params: {
               resume_token: initial_resume_token,
               form_data: {
                 name: "Test User",
               },
             },
             headers: origin_headers
        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe "/workflows/forms/waiting/:execution_id.json" do
    context "with a workflow containing a downstream form action" do
      before do
        extra =
          build_workflow_graph do |g|
            g.node "form-action-1",
                   "action:form",
                   name: "Second Page",
                   configuration: {
                     "page_type" => "page",
                     "form_fields" => [
                       { "field_label" => "Email", "field_type" => "text", "required" => false },
                       {
                         "field_label" => "Tracking ID",
                         "field_name" => "tracking_id",
                         "field_type" => "hiddenField",
                       },
                     ],
                   }
            g.node "form-completion-1",
                   "action:form",
                   name: "Completion",
                   configuration: {
                     "page_type" => "completion",
                     "on_submission" => "completion_screen",
                     "completion_title" => "={{ $json.email }}",
                     "completion_message" => "={{ $trigger.name }}",
                   }
          end
        workflow.update!(
          nodes: workflow.nodes + extra[:nodes],
          connections: [
            {
              "source_node_id" => "trigger-1",
              "target_node_id" => "form-action-1",
              "source_output_index" => 0,
              "target_input_index" => 0,
            },
            {
              "source_node_id" => "form-action-1",
              "target_node_id" => "form-completion-1",
              "source_output_index" => 0,
              "target_input_index" => 0,
            },
          ],
        )
        publish_workflow!(workflow)
      end

      it "returns signed waiting URLs without exposing the raw waiting token" do
        post form_path,
             params: {
               resume_token: initial_resume_token,
               form_data: {
                 name: "Test User",
               },
             },
             headers: origin_headers
        expect(response).to have_http_status(:ok)

        expect(response.parsed_body).not_to have_key("resume_token")
        expect(response.parsed_body["form_waiting_url"]).to be_present
        expect(response.parsed_body["form_submit_url"]).to be_present
        expect(response.parsed_body["form_status_url"]).to be_present

        execution = DiscourseWorkflows::Execution.last
        expect(execution.status).to eq("waiting")
        expect(execution.waiting_node_id).to eq("form-action-1")
        expect(
          response
            .parsed_body
            .values_at("form_waiting_url", "form_submit_url", "form_status_url")
            .join,
        ).not_to include(execution.resume_token)

        post response.parsed_body["form_submit_url"],
             params: {
               form_data: {
                 email: "test@example.com",
               },
             },
             headers: origin_headers
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).not_to have_key("resume_token")

        execution.reload
        expect(execution.status).to eq("success")
      end

      it "serves and resumes a waiting form through waiting execution endpoints" do
        post form_path,
             params: {
               resume_token: initial_resume_token,
               form_data: {
                 name: "Test User",
               },
             },
             headers: origin_headers
        expect(response).to have_http_status(:ok)

        waiting_url = response.parsed_body["form_waiting_url"]
        submit_url = response.parsed_body["form_submit_url"]
        status_url = response.parsed_body["form_status_url"]

        get status_url
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["status"]).to eq("form_waiting")

        get waiting_url
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).not_to have_key("resume_token")
        expect(response.parsed_body["fields"].first["name"]).to eq("email")

        post submit_url,
             params: {
               form_data: {
                 email: "test@example.com",
               },
             },
             headers: origin_headers
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["status"]).to eq("success")
        expect(response.parsed_body["form_completion"]).to include(
          "completion_title" => "test@example.com",
          "completion_message" => "Test User",
        )
        expect(DiscourseWorkflows::Execution.last.execution_data.context_data).not_to have_key(
          "__form_completion",
        )
        completion_step =
          DiscourseWorkflows::Execution.last.execution_data.steps_array.find do |step|
            step["node_id"] == "form-completion-1"
          end
        expect(completion_step.dig("metadata", "form_completion")).to include(
          "completion_title" => "test@example.com",
          "completion_message" => "Test User",
        )
      end

      it "returns an error when a waiting form resumes into a failing workflow" do
        extra =
          build_workflow_graph do |g|
            g.node "wait-1",
                   "flow:wait",
                   configuration: {
                     "resume" => "time_interval",
                     "wait_amount" => 0,
                     "wait_unit" => "seconds",
                   }
          end
        workflow.update!(
          nodes: workflow.nodes + extra[:nodes],
          connections: [
            {
              "source_node_id" => "trigger-1",
              "target_node_id" => "form-action-1",
              "source_output_index" => 0,
              "target_input_index" => 0,
            },
            {
              "source_node_id" => "form-action-1",
              "target_node_id" => "wait-1",
              "source_output_index" => 0,
              "target_input_index" => 0,
            },
          ],
        )
        publish_workflow!(workflow)

        post form_path,
             params: {
               resume_token: initial_resume_token,
               form_data: {
                 name: "Test User",
               },
             },
             headers: origin_headers
        expect(response).to have_http_status(:ok)

        post response.parsed_body["form_submit_url"],
             params: {
               form_data: {
                 email: "test@example.com",
               },
             },
             headers: origin_headers
        expect(response).to have_http_status(:internal_server_error)
        expect(response.parsed_body).to include(
          "status" => "error",
          "errors" => [I18n.t("discourse_workflows.errors.workflow_failed")],
        )
        expect(response.parsed_body).not_to have_key("error")
      end

      it "returns no response body when a waiting form resumes into a non-form wait" do
        update_workflow_node(workflow, "trigger-1") do |node|
          node["parameters"]["response_mode"] = "workflow_finishes"
        end
        extra =
          build_workflow_graph do |g|
            g.node "wait-1",
                   "flow:wait",
                   configuration: {
                     "resume" => "time_interval",
                     "wait_amount" => 1,
                     "wait_unit" => "hours",
                   }
          end
        workflow.update!(
          nodes: workflow.nodes + extra[:nodes],
          connections: [
            {
              "source_node_id" => "trigger-1",
              "target_node_id" => "form-action-1",
              "source_output_index" => 0,
              "target_input_index" => 0,
            },
            {
              "source_node_id" => "form-action-1",
              "target_node_id" => "wait-1",
              "source_output_index" => 0,
              "target_input_index" => 0,
            },
          ],
        )
        publish_workflow!(workflow)

        post form_path,
             params: {
               resume_token: initial_resume_token,
               form_data: {
                 name: "Test User",
               },
             },
             headers: origin_headers
        expect(response).to have_http_status(:ok)

        post response.parsed_body["form_submit_url"],
             params: {
               form_data: {
                 email: "test@example.com",
               },
             },
             headers: origin_headers
        expect(response).to have_http_status(:ok)
        expect(response.body).to be_blank
        expect(DiscourseWorkflows::Execution.last).to have_attributes(status: "waiting")
      end

      it "carries query-backed hidden values through downstream form pages" do
        get form_path, params: { tracking_id: "campaign-42" }
        expect(response).to have_http_status(:ok)

        post form_path,
             params: {
               resume_token: response.parsed_body["resume_token"],
               form_data: {
                 name: "Test User",
               },
             },
             headers: origin_headers
        expect(response).to have_http_status(:ok)

        get response.parsed_body["form_waiting_url"]
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).not_to have_key("form_fields")
        expect(response.parsed_body["fields"].pluck("name")).not_to include("tracking_id")

        post response.parsed_body["form_submit_url"],
             params: {
               form_data: {
                 email: "test@example.com",
                 tracking_id: "client-tamper",
               },
             },
             headers: origin_headers
        expect(response).to have_http_status(:ok)

        form_step =
          DiscourseWorkflows::Execution.last.execution_data.steps_array.find do |step|
            step["node_id"] == "form-action-1" &&
              step["status"] == DiscourseWorkflows::Executor::Step::SUCCESS
          end
        expect(form_step.dig("output", 0, "json")).to include(
          "email" => "test@example.com",
          "tracking_id" => "campaign-42",
          "formQueryParameters" => {
            "tracking_id" => "campaign-42",
          },
        )
      end

      it "keeps workflow_finishes submissions waiting on the next FormKit page" do
        trigger_node = workflow.nodes.find { |node| node["id"] == "trigger-1" }
        trigger_node["parameters"]["response_mode"] = "workflow_finishes"
        workflow.update!(nodes: workflow.nodes)
        publish_workflow!(workflow)

        post form_path,
             params: {
               resume_token: initial_resume_token,
               form_data: {
                 name: "Test User",
               },
             },
             headers: origin_headers
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to include(
          "response_mode" => "workflow_finishes",
          "status" => "waiting",
        )
        expect(response.parsed_body["form_waiting_url"]).to be_present

        get response.parsed_body["form_waiting_url"]
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["fields"].pluck("name")).to include("email")
      end

      it "returns sanitized HTML completion text" do
        completion_node = workflow.nodes.find { |node| node["id"] == "form-completion-1" }
        completion_node["parameters"].merge!(
          "on_submission" => "show_text",
          "completion_text" =>
            '<strong>Done</strong><script>alert("x")</script><iframe src="https://example.com"></iframe>',
        )
        workflow.update!(nodes: workflow.nodes)
        publish_workflow!(workflow)

        post form_path,
             params: {
               resume_token: initial_resume_token,
               form_data: {
                 name: "Test User",
               },
             },
             headers: origin_headers
        expect(response).to have_http_status(:ok)

        post response.parsed_body["form_submit_url"],
             params: {
               form_data: {
                 email: "test@example.com",
               },
             },
             headers: origin_headers
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["form_completion"]).to include(
          "on_submission" => "show_text",
          "completion_text" => "<strong>Done</strong>",
        )
        expect(response.parsed_body["form_completion"]["completion_text"]).not_to include(
          "script",
          "iframe",
        )
      end

      it "returns 404 when the waiting signature does not match" do
        post form_path,
             params: {
               resume_token: initial_resume_token,
               form_data: {
                 name: "Test User",
               },
             },
             headers: origin_headers
        expect(response).to have_http_status(:ok)

        get response.parsed_body["form_status_url"].sub(/signature=[^&]+/, "signature=invalid")
        expect(response).to have_http_status(:not_found)
        expect(response.parsed_body).to eq("errors" => ["not_found"])
      end

      it "returns plural errors when a waiting form resume loses the claim race" do
        post form_path,
             params: {
               resume_token: initial_resume_token,
               form_data: {
                 name: "Test User",
               },
             },
             headers: origin_headers
        submit_url = response.parsed_body["form_submit_url"]

        allow(DiscourseWorkflows::WaitingExecution).to receive(:claim).and_return(nil)

        post submit_url,
             params: {
               form_data: {
                 email: "test@example.com",
               },
             },
             headers: origin_headers
        expect(response).to have_http_status(:conflict)
        expect(response.parsed_body).to eq(
          "errors" => [I18n.t("discourse_workflows.errors.already_resumed")],
        )
      end

      it "returns 404 when execution has already been resumed" do
        post form_path,
             params: {
               resume_token: initial_resume_token,
               form_data: {
                 name: "Test User",
               },
             },
             headers: origin_headers
        submit_url = response.parsed_body["form_submit_url"]

        post submit_url,
             params: {
               form_data: {
                 email: "test@example.com",
               },
             },
             headers: origin_headers
        expect(response).to have_http_status(:ok)

        post submit_url,
             params: {
               form_data: {
                 email: "test@example.com",
               },
             },
             headers: origin_headers
        expect(response).to have_http_status(:not_found)
        expect(response.parsed_body).to eq("errors" => ["not_found"])
      end
    end
  end
end
