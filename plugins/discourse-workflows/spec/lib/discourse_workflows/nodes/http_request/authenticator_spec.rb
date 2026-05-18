# frozen_string_literal: true

RSpec.describe DiscourseWorkflows::Nodes::HttpRequest::Authenticator do
  describe ".apply" do
    it "does nothing when authentication is none" do
      headers = {}
      described_class.apply({ "authentication" => "none" }, headers, nil)

      expect(headers).not_to have_key("Authorization")
    end

    it "does nothing when authentication is not specified" do
      headers = {}
      described_class.apply({}, headers, nil)

      expect(headers).not_to have_key("Authorization")
    end

    it "raises when the auth credential slot is missing for auth modes" do
      exec_ctx =
        instance_double(
          DiscourseWorkflows::Executor::NodeExecutionContext,
          credential_reference?: false,
        )

      expect {
        described_class.apply({ "authentication" => "basic_auth" }, {}, exec_ctx)
      }.to raise_error(ArgumentError, /Credential is required/)
    end

    context "with basic_auth" do
      it "sets Authorization header with Base64 credentials" do
        headers = {}
        exec_ctx =
          instance_double(
            DiscourseWorkflows::Executor::NodeExecutionContext,
            credential_reference?: true,
            get_credentials: {
              "user" => "api_user",
              "password" => "api_pass",
            },
          )

        described_class.apply({ "authentication" => "basic_auth" }, headers, exec_ctx)

        expected = "Basic #{Base64.strict_encode64("api_user:api_pass")}"
        expect(headers["Authorization"]).to eq(expected)
        expect(exec_ctx).to have_received(:get_credentials).with("auth", 0)
      end
    end

    context "with bearer_token" do
      it "sets Bearer Authorization header" do
        headers = {}
        exec_ctx =
          instance_double(
            DiscourseWorkflows::Executor::NodeExecutionContext,
            credential_reference?: true,
            get_credentials: {
              "token" => "my-secret-token",
            },
          )

        described_class.apply({ "authentication" => "bearer_token" }, headers, exec_ctx)

        expect(headers["Authorization"]).to eq("Bearer my-secret-token")
        expect(exec_ctx).to have_received(:get_credentials).with("auth", 0)
      end
    end
  end
end
