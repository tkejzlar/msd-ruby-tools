# frozen_string_literal: true

require "webmock/rspec"
require "merck_tools"

WebMock.disable_net_connect!

RSpec.configure do |config|
  config.before(:each) do
    # Clear any ENV overrides between tests
    @saved_env = {}
  end

  config.after(:each) do
    @saved_env.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end
end

def stub_env(overrides)
  overrides.each do |k, v|
    @saved_env[k] = ENV[k] unless @saved_env.key?(k)
    ENV[k] = v
  end
end
