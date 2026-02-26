# frozen_string_literal: true

require "spec_helper"

RSpec.describe "MerckTools.load_credhub!" do
  after(:each) do
    # Clean up any env vars we set
    %w[VCAP_SERVICES JIRA_EMAIL JIRA_PASSWORD CONFLUENCE_USER CONFLUENCE_PASSWORD].each do |k|
      ENV.delete(k)
    end
  end

  it "does nothing when VCAP_SERVICES is not set" do
    ENV.delete("VCAP_SERVICES")
    expect { MerckTools.load_credhub! }.not_to raise_error
  end

  it "loads credhub credentials into ENV as uppercased keys" do
    vcap = {
      "credhub" => [
        {
          "credentials" => {
            "jira_email" => "svc@example.com",
            "jira_password" => "s3cret",
            "confluence_user" => "wiki-svc",
            "confluence_password" => "wiki-pass"
          }
        }
      ]
    }
    ENV["VCAP_SERVICES"] = vcap.to_json

    MerckTools.load_credhub!

    expect(ENV["JIRA_EMAIL"]).to eq("svc@example.com")
    expect(ENV["JIRA_PASSWORD"]).to eq("s3cret")
    expect(ENV["CONFLUENCE_USER"]).to eq("wiki-svc")
    expect(ENV["CONFLUENCE_PASSWORD"]).to eq("wiki-pass")
  end

  it "handles multiple credhub service entries" do
    vcap = {
      "credhub" => [
        { "credentials" => { "jira_email" => "jira@example.com" } },
        { "credentials" => { "confluence_user" => "wiki-svc" } }
      ]
    }
    ENV["VCAP_SERVICES"] = vcap.to_json

    MerckTools.load_credhub!

    expect(ENV["JIRA_EMAIL"]).to eq("jira@example.com")
    expect(ENV["CONFLUENCE_USER"]).to eq("wiki-svc")
  end

  it "skips gracefully when credhub key is missing from VCAP_SERVICES" do
    ENV["VCAP_SERVICES"] = '{"mysql": [{}]}'
    expect { MerckTools.load_credhub! }.not_to raise_error
  end

  it "skips entries without credentials hash" do
    ENV["VCAP_SERVICES"] = '{"credhub": [{"name": "no-creds"}]}'
    expect { MerckTools.load_credhub! }.not_to raise_error
  end
end
