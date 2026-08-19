# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "io/endpoint"

module Async
	module GRPC
		module Compatible
			# Represents readable channel credentials which can be translated into a transport-neutral TLS configuration.
			class ChannelCredentials
				# Initialize channel credentials using the same positional arguments as `GRPC::Core::ChannelCredentials.new`.
				# @parameter root_certificates [String | Nil] The trusted root certificates encoded as a PEM bundle.
				# @parameter private_key [String | Nil] The client private key encoded as PEM.
				# @parameter certificate_chain [String | Nil] The client certificate chain encoded as a PEM bundle.
				def initialize(root_certificates = nil, private_key = nil, certificate_chain = nil)
					trust_store = if root_certificates
						IO::Endpoint::TLS::TrustStore.parse(root_certificates)
					end
					
					certificates = if certificate_chain
						IO::Endpoint::TLS::Certificates.parse(certificate_chain)
					end
					
					@tls_configuration = IO::Endpoint::TLS::Configuration.new(
						trust_store: trust_store,
						certificate_chain: certificates,
						private_key: private_key,
					)
				end
				
				# @attribute [IO::Endpoint::TLS::Configuration] The transport-neutral TLS configuration.
				attr_reader :tls_configuration
			end
		end
	end
end
