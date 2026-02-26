# frozen_string_literal: true

require "uri"
require "net/http"
require "cgi"
require "json"

module MerckTools
  module MSGraph
    # Microsoft Graph client (via Merck API proxy).
    #
    # ENV vars:
    #   MS_GRAPH_BASE         – e.g. https://iapi.merck.com/microsoft-graph/v1.0
    #                           (or GRAPH_HOST for legacy compat)
    #   MS_GRAPH_API_KEY      – X-Merck-APIKey value (or GRAPH_KEY)
    #   MS_GRAPH_UPN_DOMAIN   – fallback domain for isid-based lookups (e.g. "merck.com")
    #   MS_GRAPH_OPEN_TIMEOUT – connect timeout seconds (default: 2)
    #   MS_GRAPH_READ_TIMEOUT – read timeout seconds (default: 5)
    #
    class Client
      def initialize(
        base:         ENV.fetch("MS_GRAPH_BASE") { ENV.fetch("GRAPH_HOST", "") },
        api_key:      ENV.fetch("MS_GRAPH_API_KEY") { ENV.fetch("GRAPH_KEY", "") },
        upn_domain:   ENV.fetch("MS_GRAPH_UPN_DOMAIN", "merck.com"),
        open_timeout: Integer(ENV.fetch("MS_GRAPH_OPEN_TIMEOUT", "2")),
        read_timeout: Integer(ENV.fetch("MS_GRAPH_READ_TIMEOUT", "5"))
      )
        @base         = base.to_s.sub(%r{/\z}, "")
        @api_key      = api_key.to_s
        @upn_domain   = upn_domain.to_s.strip
        @open_timeout = open_timeout
        @read_timeout = read_timeout
      end

      # Fetch user profile JSON from /users/{identifier}
      def user(identifier)
        url = "#{@base}/users/#{CGI.escape(identifier)}"
        resp = api_get(url, accept: "application/json")
        return nil unless resp[:status] == 200
        JSON.parse(resp[:body]) rescue nil
      end

      # Fetch user photo bytes.  Tries multiple identifier candidates.
      def user_photo(profile)
        candidates = build_identifier_candidates(profile)
        last = nil
        candidates.each do |id|
          res = user_photo_raw(id)
          last = res
          return res if res[:status] == 200 && res[:body].to_s.bytesize > 0
        rescue
          next
        end
        last || { status: 404, body: "", content_type: "application/octet-stream" }
      end

      # Low-level: GET /users/{id}/photo/$value
      def user_photo_raw(id_or_upn)
        url = "#{@base}/users/#{CGI.escape(id_or_upn)}/photo/$value"
        api_get(url)
      end

      # Fetch direct reports for a user.
      def direct_reports(id_or_upn, select: "companyName,userPrincipalName")
        url = "#{@base}/users/#{CGI.escape(id_or_upn)}/directReports"
        resp = api_get(url, accept: "application/json", params: { "$select" => select })
        return [] unless resp[:status] == 200
        data = JSON.parse(resp[:body]) rescue {}
        data["value"] || []
      end

      private

      def api_get(url, accept: "*/*", params: nil)
        uri = URI(url)
        uri.query = URI.encode_www_form(params) if params && !params.empty?
        req = Net::HTTP::Get.new(uri)
        req["Accept"]          = accept
        req["X-Merck-APIKey"]  = @api_key

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl      = (uri.scheme == "https")
        http.open_timeout = @open_timeout
        http.read_timeout = @read_timeout

        res = http.request(req)
        { status: res.code.to_i, body: res.body || "", content_type: res["Content-Type"] || "application/octet-stream" }
      end

      def build_identifier_candidates(profile)
        profile = profile.is_a?(Hash) ? profile : {}
        email = profile["email"].to_s.strip
        upn   = profile["userPrincipalName"].to_s.strip
        isid  = profile["isid"].to_s.strip
        domain = email_domain(email) || email_domain(upn) || @upn_domain

        cands = []
        cands << email unless email.empty?
        cands << "#{isid}@#{domain}" if !isid.empty? && !domain.empty?
        cands << isid unless isid.empty?
        cands << upn unless upn.empty?
        cands.uniq
      end

      def email_domain(val)
        s = val.to_s.strip
        s.include?("@") ? s.split("@", 2)[1] : nil
      end
    end
  end
end
