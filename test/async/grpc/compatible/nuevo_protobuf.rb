# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "async/grpc/compatible"
require "async/grpc/dispatcher"
require "async/grpc/service"
require "async/grpc/compatible/nuevo_protobuf/echo_service"
require "sus/fixtures/async/http"

class NuevoProtobufCompatibleInterface < Protocol::GRPC::Interface
	rpc :Echo,
		request_class: Async::Grpc::Compatible::Fixture::EchoRequest,
		response_class: Async::Grpc::Compatible::Fixture::EchoResponse,
		streaming: :unary
end

class NuevoProtobufCompatibleService < Async::GRPC::Service
	def echo(input, output, call)
		request = input.read
		output.write(Async::Grpc::Compatible::Fixture::EchoResponse.new(value: request.value))
	end
end

# Models the explicit client stub injection proposed for NuevoProtobuf.
class NuevoProtobufCompatibleClient < Async::Grpc::Compatible::Fixture::EchoService
	def initialize(client_stub:)
		@client_stub = client_stub
	end
	
private
	
	attr_reader :client_stub
	
	def stub
		client_stub
	end
end

describe "NuevoProtobuf client compatibility" do
	include Sus::Fixtures::Async::HTTP::ServerContext
	
	let(:protocol) {Async::HTTP::Protocol::HTTP2}
	let(:service_name) {"async.grpc.compatible.fixture.EchoService"}
	let(:service) {NuevoProtobufCompatibleService.new(NuevoProtobufCompatibleInterface, service_name)}
	let(:app) {Async::GRPC::Dispatcher.new(services: {service_name => service})}
	let(:grpc_client) {Async::GRPC::Client.new(client)}
	let(:channel) {Async::GRPC::Compatible::Channel.new(client: grpc_client)}
	let(:client_stub) {Async::GRPC::Compatible::ClientStub.new("unused", nil, channel_override: channel)}
	let(:nuevo_protobuf_client) {NuevoProtobufCompatibleClient.new(client_stub: client_stub)}
	
	it "performs a unary request using a generated client" do
		request = Async::Grpc::Compatible::Fixture::EchoRequest.new(value: "Hello")
		response, error = nuevo_protobuf_client.echo(request)
		
		expect(error).to be_nil
		expect(response).to be_a(Async::Grpc::Compatible::Fixture::EchoResponse)
		expect(response.value).to be == "Hello"
	end
end
