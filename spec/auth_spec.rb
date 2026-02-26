# frozen_string_literal: true

require "spec_helper"

RSpec.describe MerckTools::Auth::OAuthClient do
  let(:client) do
    described_class.new(
      base: "https://auth.example.com/v2",
      client_id: "my-id",
      client_secret: "my-secret",
      redirect_uri: "https://app.example.com/callback",
      scope: "default",
      login_method: "sso"
    )
  end

  describe "#authorize_url" do
    it "builds a valid authorize URL" do
      url = client.authorize_url(state: "abc123")
      expect(url).to start_with("https://auth.example.com/v2/authorize?")
      expect(url).to include("client_id=my-id")
      expect(url).to include("state=abc123")
      expect(url).to include("response_type=code")
      expect(url).to include("login_method=sso")
    end
  end

  describe "#exchange_code" do
    it "posts to the token endpoint" do
      stub_request(:post, "https://auth.example.com/v2/token")
        .to_return(
          status: 200,
          body: { access_token: "at-123", refresh_token: "rt-456" }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      result = client.exchange_code(code: "auth-code-xyz")
      expect(result[:status]).to eq(200)
      expect(result[:json]["access_token"]).to eq("at-123")
    end
  end

  describe "#introspect" do
    it "checks token validity" do
      stub_request(:post, "https://auth.example.com/v2/introspect")
        .to_return(
          status: 200,
          body: { active: true }.to_json
        )

      result = client.introspect(token: "at-123")
      expect(result[:json]["active"]).to be true
    end
  end

  describe "#userinfo" do
    it "fetches user profile" do
      stub_request(:get, "https://auth.example.com/v2/userinfo")
        .with(headers: { "Authorization" => "Bearer at-123" })
        .to_return(
          status: 200,
          body: { isid: "jdoe", email: "jdoe@merck.com" }.to_json
        )

      result = client.userinfo(access_token: "at-123")
      expect(result[:json]["isid"]).to eq("jdoe")
    end
  end
end

RSpec.describe MerckTools::Auth::DevAuth do
  before { stub_env("DEV_AUTH" => "1", "DEV_AUTH_PASSPHRASE" => "") }

  describe ".enabled?" do
    it "returns true when DEV_AUTH=1" do
      expect(described_class.enabled?).to be true
    end

    it "checks environment when provided" do
      expect(described_class.enabled?("development")).to be true
      expect(described_class.enabled?("production")).to be false
    end
  end

  describe ".profile_from_headers" do
    it "builds profile from dev headers" do
      headers = {
        "HTTP_X_DEV_USER"  => "jdoe@merck.com",
        "HTTP_X_DEV_NAME"  => "John Doe",
        "HTTP_X_DEV_ROLES" => "admin,editor",
        "HTTP_X_DEV_ISID"  => "jdoe"
      }
      profile = described_class.profile_from_headers(headers)
      expect(profile["email"]).to eq("jdoe@merck.com")
      expect(profile["name"]).to eq("John Doe")
      expect(profile["roles"]).to eq(["admin", "editor"])
      expect(profile["isid"]).to eq("jdoe")
    end

    it "returns nil when disabled" do
      stub_env("DEV_AUTH" => "0")
      profile = described_class.profile_from_headers({ "HTTP_X_DEV_USER" => "x@y.com" })
      expect(profile).to be_nil
    end
  end
end
