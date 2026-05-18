# frozen_string_literal: true

RSpec.describe DiscourseWorkflows::Executor::NodeExecutionContext do
  describe "#get_context" do
    it "exposes only node-scoped mutable context to node implementations" do
      ctx = described_class.new(input_items: [], resolver: nil, node_context: { "index" => 1 })

      expect(ctx.get_context).to eq("index" => 1)
      expect { ctx.get_context(:flow) }.to raise_error(
        ArgumentError,
        "Unknown context scope: flow. Use :node",
      )
    end
  end

  describe "#input_context" do
    it "returns the public input context for node execution" do
      ctx =
        described_class.new(
          input_items: [],
          resolver: nil,
          node_context: {
            "no_items_left" => true,
          },
        )

      expect(ctx.input_context).to eq("noItemsLeft" => true)
    end
  end

  describe "#helpers" do
    it "normalizes n8n-compatible items through execution helpers" do
      ctx = described_class.new(input_items: [], resolver: nil)

      expect(ctx.helpers.normalize_items([{ json: { name: "Ada" }, pairedItem: 0 }])).to eq(
        [{ "json" => { "name" => "Ada" }, "pairedItem" => { "item" => 0 } }],
      )
    end
  end

  describe "#resume_action_id" do
    it "returns a signed action id for interactive resume nodes" do
      ctx =
        described_class.new(
          input_items: [],
          resolver: nil,
          execution_id: 123,
          resume_token: "resume-token",
        )

      payload =
        DiscourseWorkflows::InteractiveResume.action_payload(ctx.resume_action_id("approve"))

      expect(payload).to include("execution_id" => 123, "action" => "approve")
    end
  end

  describe "#get_node_parameters" do
    it "resolves $json expressions against the item passed in, not a cached first item" do
      config = { "value" => "={{ $json.x }}" }
      schema = { value: { type: :string } }
      sandbox = DiscourseWorkflows::JsSandbox.new({ "$json" => {} })
      resolver = DiscourseWorkflows::ExpressionResolver.new({ "$json" => {} }, sandbox: sandbox)

      ctx =
        described_class.new(
          input_items: [],
          parameters: config,
          property_schema: schema,
          resolver: resolver,
        )

      first = ctx.get_node_parameters({ "json" => { "x" => "ITEM_ONE" } })
      second = ctx.get_node_parameters({ "json" => { "x" => "ITEM_TWO" } })

      expect(first).to eq("value" => "ITEM_ONE")
      expect(second).to eq("value" => "ITEM_TWO")
    ensure
      resolver&.dispose
      sandbox&.dispose
    end
  end

  describe "#get_node_parameter" do
    it "resolves a nested parameter path against the current item" do
      ctx, resolver, sandbox =
        build_parameter_context({ "outer" => { "inner" => "={{ $json.value }}" } })

      value = ctx.get_node_parameter("outer.inner", { "json" => { "value" => "resolved" } })

      expect(value).to eq("resolved")
    ensure
      resolver&.dispose
      sandbox&.dispose
    end

    it "returns the default for a missing parameter path" do
      ctx, resolver, sandbox = build_parameter_context({ "outer" => {} })

      value = ctx.get_node_parameter("outer.inner", { "json" => {} }, default: "default-value")

      expect(value).to eq("default-value")
    ensure
      resolver&.dispose
      sandbox&.dispose
    end

    it "evaluates condition-builder parameters even when the root key is absent" do
      ctx, resolver, sandbox =
        build_parameter_context({}, schema: { conditions: { ui: { control: :condition_builder } } })

      value = ctx.get_node_parameter(:conditions, { "json" => {} })

      expect(value).to eq(true)
    ensure
      resolver&.dispose
      sandbox&.dispose
    end

    it "returns literal values for no_data_expression fields" do
      ctx, resolver, sandbox =
        build_parameter_context(
          { "code" => "={{ $json.value }}" },
          schema: {
            code: {
              type: :string,
              no_data_expression: true,
            },
          },
        )

      value = ctx.get_node_parameter("code", { "json" => { "value" => "resolved" } })

      expect(value).to eq("={{ $json.value }}")
    ensure
      resolver&.dispose
      sandbox&.dispose
    end

    it "returns raw stored values when raw_expressions is requested" do
      ctx, resolver, sandbox = build_parameter_context({ "message" => "={{ $json.value }}" })

      resolved = ctx.get_node_parameter("message", { "json" => { "value" => "resolved" } })
      raw =
        ctx.get_node_parameter(
          "message",
          { "json" => { "value" => "resolved" } },
          options: {
            raw_expressions: true,
          },
        )

      expect(resolved).to eq("resolved")
      expect(raw).to eq("={{ $json.value }}")
    ensure
      resolver&.dispose
      sandbox&.dispose
    end

    it "coerces resolved values when an ensure_type is provided" do
      ctx, resolver, sandbox = build_parameter_context({ "count" => "={{ $json.count }}" })

      value =
        ctx.get_node_parameter("count", { "json" => { "count" => "4" } }, ensure_type: :integer)

      expect(value).to eq(4)
    ensure
      resolver&.dispose
      sandbox&.dispose
    end
  end

  describe "#get_fixed_collection_rows" do
    it "returns resolved fixed collection rows for the current item" do
      ctx, resolver, sandbox =
        build_parameter_context(
          { "params" => { "values" => [{ "name" => "user_id", "value" => "={{ $json.id }}" }] } },
        )

      rows = ctx.get_fixed_collection_rows("params", { "json" => { "id" => 42 } })

      expect(rows).to eq([{ "name" => "user_id", "value" => 42 }])
    ensure
      resolver&.dispose
      sandbox&.dispose
    end

    it "keeps nested no_data_expression fields literal while resolving other row fields" do
      ctx, resolver, sandbox =
        build_parameter_context(
          {
            "columns" => {
              "values" => [{ "header" => "={{ $json.label }}", "value" => "={{ $json.value }}" }],
            },
          },
          schema: {
            columns: {
              type: :fixed_collection,
              options: [
                {
                  name: "values",
                  values: {
                    header: {
                      type: :string,
                      no_data_expression: true,
                    },
                    value: {
                      type: :string,
                    },
                  },
                },
              ],
            },
          },
        )

      rows =
        ctx.get_fixed_collection_rows(
          "columns",
          { "json" => { "label" => "Name", "value" => "Ada" } },
        )

      expect(rows).to eq([{ "header" => "={{ $json.label }}", "value" => "Ada" }])
    ensure
      resolver&.dispose
      sandbox&.dispose
    end

    it "returns the default when the collection path is missing" do
      default = [{ "name" => "fallback", "value" => "1" }]
      ctx, resolver, sandbox = build_parameter_context({})

      rows = ctx.get_fixed_collection_rows("params", { "json" => {} }, default: default)

      expect(rows).to eq(default)
    ensure
      resolver&.dispose
      sandbox&.dispose
    end

    it "returns an empty array when the collection is present but empty" do
      default = [{ "name" => "fallback", "value" => "1" }]
      ctx, resolver, sandbox = build_parameter_context({ "params" => { "values" => [] } })

      rows = ctx.get_fixed_collection_rows("params", { "json" => {} }, default: default)

      expect(rows).to eq([])
    ensure
      resolver&.dispose
      sandbox&.dispose
    end
  end

  describe "#get_collection_options" do
    it "returns resolved option bag values" do
      ctx, resolver, sandbox =
        build_parameter_context({ "options" => { "ignore_conversion_errors" => "={{ true }}" } })

      options = ctx.get_collection_options("options", { "json" => {} })

      expect(options).to eq("ignore_conversion_errors" => true)
    ensure
      resolver&.dispose
      sandbox&.dispose
    end

    it "returns the default when the option bag path is missing" do
      default = { "dot_notation" => true }
      ctx, resolver, sandbox = build_parameter_context({})

      options = ctx.get_collection_options("options", { "json" => {} }, default: default)

      expect(options).to eq(default)
    ensure
      resolver&.dispose
      sandbox&.dispose
    end
  end

  describe "#get_credential" do
    fab!(:admin)
    fab!(:credential) do
      Fabricate(
        :discourse_workflows_credential,
        credential_type: "basic_auth",
        data:
          DiscourseWorkflows::CredentialEncryptor.encrypt(
            { "user" => "={{ $json.username }}", "password" => "static-password" },
          ),
      )
    end

    it "decrypts and resolves credential expressions against the current item" do
      resolver_context = { "$json" => {} }
      sandbox = DiscourseWorkflows::JsSandbox.new(resolver_context)
      resolver = DiscourseWorkflows::ExpressionResolver.new(resolver_context, sandbox: sandbox)
      ctx =
        described_class.new(
          input_items: [],
          parameters: {
            "authentication" => "basic_auth",
          },
          credentials: {
            "auth" => {
              "id" => credential.id,
              "credential_type" => "basic_auth",
            },
          },
          credential_schema: DiscourseWorkflows::Nodes::HttpRequest::V1.credentials,
          resolver: resolver,
        )

      resolved =
        ctx.with_item({ "json" => { "username" => "item-user" } }) { ctx.get_credential("auth") }

      expect(resolved).to eq("user" => "item-user", "password" => "static-password")
    ensure
      resolver&.dispose
      sandbox&.dispose
    end

    it "allows access when the current workflow node references the credential" do
      workflow = workflow_with_credential_dependency(credential)
      ctx, resolver, sandbox = build_credential_context(workflow: workflow)

      resolved =
        ctx.with_item({ "json" => { "username" => "dependency-user" } }) do
          ctx.get_credential("auth")
        end

      expect(resolved).to eq("user" => "dependency-user", "password" => "static-password")
    ensure
      resolver&.dispose
      sandbox&.dispose
    end

    it "denies access when the current workflow node does not reference the credential" do
      workflow = workflow_with_credential_dependency(credential)
      DiscourseWorkflows::WorkflowDependency.where(workflow_id: workflow.id).delete_all
      ctx, resolver, sandbox = build_credential_context(workflow: workflow)

      expect { ctx.get_credential("auth") }.to raise_error(Discourse::InvalidAccess)
    ensure
      resolver&.dispose
      sandbox&.dispose
    end

    it "rejects undeclared credential slots" do
      ctx, resolver, sandbox =
        build_credential_context(
          credentials: {
            "other" => {
              "id" => credential.id,
              "credential_type" => "basic_auth",
            },
          },
        )

      expect { ctx.get_credential("other") }.to raise_error(Discourse::InvalidAccess)
    ensure
      resolver&.dispose
      sandbox&.dispose
    end

    it "raises when the node is not configured to use the requested credential" do
      resolver_context = { "$json" => {} }
      sandbox = DiscourseWorkflows::JsSandbox.new(resolver_context)
      resolver = DiscourseWorkflows::ExpressionResolver.new(resolver_context, sandbox: sandbox)
      ctx =
        described_class.new(
          input_items: [],
          parameters: {
            "authentication" => "basic_auth",
          },
          credentials: {
            "auth" => {
              "id" => credential.id + 1,
              "credential_type" => "basic_auth",
            },
          },
          credential_schema: DiscourseWorkflows::Nodes::HttpRequest::V1.credentials,
          resolver: resolver,
        )

      expect { ctx.get_credential("auth") }.to raise_error(Discourse::InvalidAccess)
    ensure
      resolver&.dispose
      sandbox&.dispose
    end
  end

  describe "#helpers" do
    fab!(:admin)
    fab!(:data_table, :discourse_workflows_data_table)

    it "returns a Data Table node proxy for the requested data table when config references it" do
      ctx =
        described_class.new(
          input_items: [],
          parameters: {
            "data_table_id" => data_table.id,
          },
          node_identifier: "action:data_table",
          resolver: nil,
        )

      expect(ctx.helpers.get_data_table_proxy(data_table.id)).to be_a(
        DiscourseWorkflows::DataTables::NodeProxy,
      )
    end

    it "allows access when the current workflow node references the data table" do
      workflow = workflow_with_data_table_dependency(data_table)
      ctx = build_data_table_context(workflow: workflow)

      expect(ctx.helpers.get_data_table_proxy(data_table.id)).to be_a(
        DiscourseWorkflows::DataTables::NodeProxy,
      )
    end

    it "returns a Data Table aggregate proxy for allowed nodes" do
      ctx = build_data_table_context

      expect(ctx.helpers.get_data_table_aggregate_proxy).to be_a(
        DiscourseWorkflows::DataTables::AggregateNodeProxy,
      )
    end

    it "denies access when the current workflow node does not reference the data table" do
      workflow = workflow_with_data_table_dependency(data_table)
      DiscourseWorkflows::WorkflowDependency.where(workflow_id: workflow.id).delete_all
      ctx = build_data_table_context(workflow: workflow)

      expect { ctx.helpers.get_data_table_proxy(data_table.id) }.to raise_error(
        Discourse::InvalidAccess,
      )
    end

    it "does not reveal whether an unauthorized data table id exists" do
      ctx = build_data_table_context(configuration: { "data_table_id" => data_table.id + 1 })

      expect { ctx.helpers.get_data_table_proxy(data_table.id) }.to raise_error(
        Discourse::InvalidAccess,
      )
    end

    it "raises when the node is not configured to use the requested data table" do
      ctx =
        described_class.new(
          input_items: [],
          parameters: {
            "data_table_id" => data_table.id + 1,
          },
          node_identifier: "action:data_table",
          resolver: nil,
        )

      expect { ctx.helpers.get_data_table_proxy(data_table.id) }.to raise_error(
        Discourse::InvalidAccess,
      )
    end

    it "does not expose Data Table helpers to other node types" do
      ctx =
        described_class.new(
          input_items: [],
          parameters: {
            "data_table_id" => data_table.id,
          },
          node_identifier: "action:badge",
          resolver: nil,
        )

      expect { ctx.helpers.get_data_table_proxy(data_table.id) }.to raise_error(
        Discourse::InvalidAccess,
      )
    end
  end

  describe "#find_user" do
    fab!(:user)

    it "finds a user by username" do
      ctx = described_class.new(input_items: [], resolver: nil)

      expect(ctx.find_user(username: user.username)).to eq(user)
    end

    it "finds a user by id" do
      ctx = described_class.new(input_items: [], resolver: nil)

      expect(ctx.find_user(id: user.id)).to eq(user)
    end

    it "raises a node error when the username cannot be found" do
      ctx = described_class.new(input_items: [], resolver: nil)

      expect { ctx.find_user(username: "nonexistent_user") }.to raise_error(
        DiscourseWorkflows::NodeError,
        "User 'nonexistent_user' not found",
      )
    end

    it "raises a node error when the id cannot be found" do
      ctx = described_class.new(input_items: [], resolver: nil)

      expect { ctx.find_user(id: -999) }.to raise_error(
        DiscourseWorkflows::NodeError,
        "User with id -999 not found",
      )
    end

    it "requires exactly one lookup key" do
      ctx = described_class.new(input_items: [], resolver: nil)

      expect { ctx.find_user }.to raise_error(
        ArgumentError,
        "Provide exactly one of username or id",
      )
      expect { ctx.find_user(username: user.username, id: user.id) }.to raise_error(
        ArgumentError,
        "Provide exactly one of username or id",
      )
    end
  end

  describe "#http_request" do
    it "returns a parsed response object" do
      stub_request(:get, "https://api.example.com/data").to_return(
        status: 200,
        body: { ok: true }.to_json,
        headers: {
          "content-type" => "application/json",
        },
      )

      ctx = described_class.new(input_items: [], resolver: nil)
      response = ctx.http_request(method: "GET", url: "https://api.example.com/data")

      expect(response.status).to eq(200)
      expect(response.headers).to include("content-type" => "application/json")
      expect(response.body).to eq("ok" => true)
    end

    it "does not retry transient GET response statuses by default" do
      stub_request(:get, "https://api.example.com/retry").to_return(
        { status: 503, body: "unavailable" },
        {
          status: 200,
          body: { ok: true }.to_json,
          headers: {
            "content-type" => "application/json",
          },
        },
      )

      ctx = described_class.new(input_items: [], resolver: nil)

      expect {
        ctx.http_request(method: "GET", url: "https://api.example.com/retry")
      }.to raise_error(
        RuntimeError,
        "HTTP GET https://api.example.com/retry failed with status 503",
      )
      expect(WebMock).to have_requested(:get, "https://api.example.com/retry").once
    end

    it "does not retry non-GET transient response statuses by default" do
      stub_request(:post, "https://api.example.com/retry").to_return(
        status: 503,
        body: "unavailable",
      )

      ctx = described_class.new(input_items: [], resolver: nil)

      expect {
        ctx.http_request(method: "POST", url: "https://api.example.com/retry")
      }.to raise_error(
        RuntimeError,
        "HTTP POST https://api.example.com/retry failed with status 503",
      )
      expect(WebMock).to have_requested(:post, "https://api.example.com/retry").once
    end

    it "allows callers to opt non-GET requests into retries" do
      stub_request(:post, "https://api.example.com/retry").to_return(
        { status: 503, body: "unavailable" },
        {
          status: 200,
          body: { ok: true }.to_json,
          headers: {
            "content-type" => "application/json",
          },
        },
      )

      ctx = described_class.new(input_items: [], resolver: nil)
      response =
        ctx.http_request(
          method: "POST",
          url: "https://api.example.com/retry",
          options: {
            max_retries: 1,
          },
        )

      expect(response.status).to eq(200)
      expect(WebMock).to have_requested(:post, "https://api.example.com/retry").twice
    end
  end

  describe "#put_execution_to_wait" do
    it "defaults to not waiting" do
      ctx = described_class.new(input_items: [], resolver: nil)
      expect(ctx).not_to be_waiting
      expect(ctx.waiting_until).to be_nil
    end

    it "flags the context as waiting with the given deadline" do
      ctx = described_class.new(input_items: [], resolver: nil)
      deadline = 2.hours.from_now

      ctx.put_execution_to_wait(deadline)

      expect(ctx).to be_waiting
      expect(ctx.waiting_until).to eq(deadline)
    end

    it "accepts a nil deadline to request the executor ceiling" do
      ctx = described_class.new(input_items: [], resolver: nil)

      ctx.put_execution_to_wait(nil)

      expect(ctx).to be_waiting
      expect(ctx.waiting_until).to be_nil
    end
  end

  def workflow_with_data_table_dependency(data_table)
    graph =
      build_workflow_graph do |g|
        g.node "dt-1", "action:data_table", configuration: { "data_table_id" => data_table.id }
      end
    Fabricate(:discourse_workflows_workflow, created_by: admin, **graph)
  end

  def build_data_table_context(workflow: nil, configuration: { "data_table_id" => data_table.id })
    described_class.new(
      input_items: [],
      parameters: configuration,
      resolver: nil,
      workflow: workflow,
      node_id: workflow ? "dt-1" : nil,
      node_identifier: "action:data_table",
    )
  end

  def workflow_with_credential_dependency(credential)
    graph =
      build_workflow_graph do |g|
        g.node "http-1",
               "action:http_request",
               parameters: {
                 "authentication" => "basic_auth",
               },
               credentials: {
                 "auth" => {
                   "id" => credential.id,
                   "credential_type" => "basic_auth",
                 },
               }
      end
    Fabricate(:discourse_workflows_workflow, created_by: admin, **graph)
  end

  def build_credential_context(
    workflow: nil,
    configuration: { "authentication" => "basic_auth" },
    credentials: { "auth" => { "id" => credential.id, "credential_type" => "basic_auth" } }
  )
    resolver_context = { "$json" => {} }
    sandbox = DiscourseWorkflows::JsSandbox.new(resolver_context)
    resolver = DiscourseWorkflows::ExpressionResolver.new(resolver_context, sandbox: sandbox)
    ctx =
      described_class.new(
        input_items: [],
        parameters: configuration,
        credentials: credentials,
        credential_schema: DiscourseWorkflows::Nodes::HttpRequest::V1.credentials,
        resolver: resolver,
        workflow: workflow,
        node_id: workflow ? "http-1" : nil,
      )
    [ctx, resolver, sandbox]
  end

  def build_parameter_context(parameters = nil, schema: {}, **keyword_parameters)
    parameters ||= keyword_parameters
    resolver_context = { "$json" => {} }
    sandbox = DiscourseWorkflows::JsSandbox.new(resolver_context)
    resolver = DiscourseWorkflows::ExpressionResolver.new(resolver_context, sandbox: sandbox)
    ctx =
      described_class.new(
        input_items: [],
        parameters: parameters,
        property_schema: schema,
        resolver: resolver,
      )
    [ctx, resolver, sandbox]
  end
end
