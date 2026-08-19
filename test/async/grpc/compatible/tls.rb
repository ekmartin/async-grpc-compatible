# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "async/grpc/compatible"
require "async/grpc/compatible/tls_fixture"
require "async/grpc/dispatcher"
require "async/grpc/service"
require "sus/fixtures/async/http"
require "uri"

class TLSCompatibleMessage
	def self.decode(payload)
		new(payload)
	end
	
	def initialize(value)
		@value = value
	end
	
	attr_reader :value
	
	def to_proto
		@value
	end
end

class TLSCompatibleInterface < Protocol::GRPC::Interface
	rpc :Echo,
		request_class: TLSCompatibleMessage,
		response_class: TLSCompatibleMessage,
		streaming: :unary
end

class TLSCompatibleService < Async::GRPC::Service
	def echo(input, output, _call)
		output.write(input.read)
	end
end

describe "compatible TLS channel credentials" do
	include Sus::Fixtures::Async::HTTP::ServerContext
	
	let(:protocol) {Async::HTTP::Protocol::HTTP2}
	let(:url) {"https://localhost:0"}
	let(:service_name) {"compatible.TLSService"}
	let(:service) {TLSCompatibleService.new(TLSCompatibleInterface, service_name)}
	let(:app) {Async::GRPC::Dispatcher.new(services: {service_name => service})}
	
	let(:certificate_issuer) {Async::GRPC::Compatible::TLSFixture::CERTIFICATE_ISSUER}
	let(:server_authority) {Async::GRPC::Compatible::TLSFixture::SERVER_AUTHORITY}
	def build_server_tls_context
		server_authority.server_context.tap do |context|
			context.alpn_protocols = protocol.names
		end
	end
	
	let(:server_tls_context) {build_server_tls_context}
	
	def endpoint_options
		super.merge(ssl_context: server_tls_context)
	end
	
	def secure_target
		"localhost:#{URI(bound_url).port}"
	end
	
	def request_with(credentials)
		client_stub = Async::GRPC::Compatible::ClientStub.new(secure_target, credentials)
		response = client_stub.request_response(
			"/#{service_name}/Echo",
			TLSCompatibleMessage.new("Hello"),
			->(message){message.to_proto},
			TLSCompatibleMessage.method(:decode),
		)
		
		return response
	ensure
		client_stub&.close
	end
	
	it "trusts a server using custom root certificates" do
		credentials = Async::GRPC::Compatible::ChannelCredentials.new(certificate_issuer.certificate.to_pem)
		
		expect(request_with(credentials).value).to be == "Hello"
	end
	
	it "rejects a server signed by an untrusted certificate authority" do
		untrusted_issuer = Async::GRPC::Compatible::TLSFixture::UNTRUSTED_ISSUER
		credentials = Async::GRPC::Compatible::ChannelCredentials.new(untrusted_issuer.certificate.to_pem)
		
		expect do
			request_with(credentials)
		end.to raise_exception(OpenSSL::SSL::SSLError)
	end
	
	with "a server which requires a client certificate" do
		let(:client_authority) {Async::GRPC::Compatible::TLSFixture::CLIENT_AUTHORITY}
		let(:server_tls_context) do
			build_server_tls_context.tap do |context|
				context.cert_store = server_authority.store
				context.verify_mode = OpenSSL::SSL::VERIFY_PEER | OpenSSL::SSL::VERIFY_FAIL_IF_NO_PEER_CERT
			end
		end
		
		it "authenticates using a client certificate and private key" do
			credentials = Async::GRPC::Compatible::ChannelCredentials.new(
				certificate_issuer.certificate.to_pem,
				client_authority.key.to_pem,
				client_authority.certificate.to_pem + certificate_issuer.certificate.to_pem,
			)
			
			expect(request_with(credentials).value).to be == "Hello"
		end
		
		it "rejects a client without a certificate" do
			credentials = Async::GRPC::Compatible::ChannelCredentials.new(certificate_issuer.certificate.to_pem)
			
			begin
				request_with(credentials)
			rescue OpenSSL::SSL::SSLError, EOFError => error
				expect([OpenSSL::SSL::SSLError, EOFError]).to be(:include?, error.class)
			else
				expect(false).to be == true
			end
		end
	end
end
