# frozen_string_literal: true

module MerckTools
  module Auth
    # Development-mode authentication bypass.
    #
    # When enabled, allows impersonation via HTTP headers (X-Dev-User, etc.)
    # without hitting the real OAuth provider.
    #
    # ENV vars:
    #   DEV_AUTH            – set to "1" to enable
    #   DEV_AUTH_PASSPHRASE – optional passphrase guard
    #
    module DevAuth
      def self.enabled?(env = nil)
        ENV["DEV_AUTH"] == "1" && (env.nil? || env.to_s == "development")
      end

      def self.passphrase_ok?(pw)
        expected = ENV["DEV_AUTH_PASSPHRASE"].to_s
        return true if expected.empty?
        !pw.to_s.empty? && secure_compare(pw.to_s, expected)
      end

      # Build a user profile hash from dev headers.
      # Returns nil if dev auth is not enabled or headers are missing.
      def self.profile_from_headers(headers, env: nil)
        return nil unless enabled?(env)

        email = headers["HTTP_X_DEV_USER"] || headers["X-Dev-User"]
        return nil unless email && email.include?("@")

        name  = headers["HTTP_X_DEV_NAME"]  || headers["X-Dev-Name"]  || email.split("@").first
        roles = (headers["HTTP_X_DEV_ROLES"] || headers["X-Dev-Roles"] || "").split(",").map(&:strip)
        isid  = headers["HTTP_X_DEV_ISID"]  || headers["X-Dev-Isid"]

        {
          "email"       => email,
          "name"        => name,
          "given_name"  => name.split(" ", 2)[0],
          "family_name" => name.split(" ", 2)[1] || "",
          "roles"       => roles,
          "isid"        => isid
        }
      end

      def self.secure_compare(a, b)
        return false if a.bytesize != b.bytesize
        l = a.unpack("C*")
        r = b.unpack("C*")
        l.zip(r).reduce(0) { |acc, (x, y)| acc | (x ^ y) } == 0
      end
      private_class_method :secure_compare
    end
  end
end
