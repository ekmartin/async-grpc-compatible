# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "localhost"

module Async
	module GRPC
		module Compatible
			module TLSFixture
				CERTIFICATE_ISSUER = Localhost::Issuer.new("async-grpc-compatible-test")
				SERVER_AUTHORITY = Localhost::Authority.new("localhost", issuer: CERTIFICATE_ISSUER)
				CLIENT_AUTHORITY = Localhost::Authority.new("client", issuer: CERTIFICATE_ISSUER)
				UNTRUSTED_ISSUER = Localhost::Issuer.new("async-grpc-compatible-untrusted-test")
			end
		end
	end
end
