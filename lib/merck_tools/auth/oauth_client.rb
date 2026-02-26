# frozen_string_literal: true

require "uri"
require "net/http"
require "json"
require "base64"

module MerckTools
  module Auth
    # Standalone OAuth 2.0 client for Merck SSO (authentication-service/v2).
    #
    # Framework-agnostic — returns plain hashes; the consumer wires cookies,
    # session, and redirects in their own web layer.
    #
    # ENV vars:
    #   OAUTH_BASE          – token/authorize/introspect base URL
    #                         (default: https://iapi-test.merck.com/authentication-service/v2)
    #   OAUTH_CLIENT_ID     – OAuth client id
    #   OAUTH_CLIENT_SECRET – OAuth client secret
    #   OAUTH_REDIRECT_URI  – registered callback URL
    #   OAUTH_SCOPE         – scope string (default: "default")
    #   OAUTH_LOGIN_METHOD  – login_method param (default: "sso")
    #
    class OAuthClient
      attr_reader :base, :client_id, :redirect_uri, :scope, :login_method

      def initialize(
        base:         ENV.fetch("OAUTH_BASE") { ENV.fetch("OAUTH_HOST", "https://iapi-test.merck.com/authentication-service/v2") },
        client_id:    ENV.fetch("OAUTH_CLIENT_ID") { ENV["OAUTH_KEY"] },
        client_secret: ENV.fetch("OAUTH_CLIENT_SECRET") { ENV["OAUTH_SECRET"] },
        redirect_uri: ENV["OAUTH_REDIRECT_URI"],
        scope:        ENV.fetch("OAUTH_SCOPE", "default"),
        login_method: ENV.fetch("OAUTH_LOGIN_METHOD", "sso")
      )
        @base          = base.to_s.sub(%r{/\z}, "")
        @client_id     = client_id.to_s
        @client_secret = client_secret.to_s
        @redirect_uri  = redirect_uri.to_s
        @scope         = scope
        @login_method  = login_method
      end

      # Build the URL the browser should be redirected to.
      def authorize_url(state:, redirect_uri: @redirect_uri)
        uri = URI("#{@base}/authorize")
        uri.query = URI.encode_www_form(
          response_type: "code",
          client_id:     @client_id,
          redirect_uri:  redirect_uri,
          scope:         @scope,
          state:         state,
          login_method:  @login_method
        )
        uri.to_s
      end

      # Exchange authorization code for tokens.
      # Returns { status:, json: { "access_token" => ..., "refresh_token" => ... } }
      def exchange_code(code:, redirect_uri: @redirect_uri)
        post_form("#{@base}/token",
          grant_type:   "authorization_code",
          code:         code,
          redirect_uri: redirect_uri,
          scope:        @scope
        )
      end

      # Refresh an expired access token.
      def refresh_token(refresh_token:)
        post_form("#{@base}/token",
          grant_type:    "refresh_token",
          refresh_token: refresh_token,
          scope:         @scope
        )
      end

      # Introspect a token (check if still active).
      def introspect(token:, token_type_hint: "access_token")
        post_form("#{@base}/introspect",
          token:           token,
          token_type_hint: token_type_hint
        )
      end

      # Fetch user profile from /userinfo.
      def userinfo(access_token:)
        get_json("#{@base}/userinfo", bearer: access_token)
      end

      private

      def basic_auth_header
        # Some deployments provide a pre-encoded Base64 string as the secret
        # (long, no colons, valid Base64 chars only). In that case, use it as-is.
        # Otherwise, encode the standard "client_id:client_secret" pair.
        encoded = if pre_encoded_secret?
                    @client_secret
                  else
                    Base64.strict_encode64("#{@client_id}:#{@client_secret}")
                  end
        "Basic #{encoded}"
      end

      def pre_encoded_secret?
        @client_secret.length >= 20 &&
          !@client_secret.include?(":") &&
          @client_secret.match?(%r{\A[A-Za-z0-9+/]+=*\z})
      end

      def post_form(url, form_hash)
        uri = URI(url)
        req = Net::HTTP::Post.new(uri)
        req["Accept"]        = "application/json"
        req["Authorization"] = basic_auth_header
        req["Content-Type"]  = "application/x-www-form-urlencoded"
        req.body = URI.encode_www_form(form_hash)
        do_http(uri, req)
      end

      def get_json(url, bearer: nil)
        uri = URI(url)
        req = Net::HTTP::Get.new(uri)
        req["Accept"]        = "application/json"
        req["Authorization"] = "Bearer #{bearer}" if bearer
        do_http(uri, req)
      end

      def do_http(uri, req)
        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
          res = http.request(req)
          body = res.body.to_s
          json = begin
            JSON.parse(body)
          rescue JSON::ParserError
            { "raw" => body }
          end
          { status: res.code.to_i, json: json }
        end
      end
    end
  end
end
