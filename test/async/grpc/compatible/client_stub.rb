# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "async/grpc/compatible"
require "async/grpc/dispatcher"
require "async/grpc/service"
require "base64"
require "sus/fixtures/async/http"

class CompatibleMessage
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

class CompatibleInterface < Protocol::GRPC::Interface
	rpc :Echo,
		request_class: CompatibleMessage,
		response_class: CompatibleMessage,
		streaming: :unary
end

class CompatibleService < Async::GRPC::Service
	def echo(input, output, call)
		request = input.read
		
		case request.value
		when "error"
			call.response.headers["x-error"] = "metadata"
			call.response.headers["x-error-bin"] = Base64.strict_encode64("binary metadata")
			Protocol::GRPC::Metadata.assign_status!(
				call.response.headers,
				status: Protocol::GRPC::Status::NOT_FOUND,
				message: "Missing"
			)
		when "slow"
			sleep(0.1)
			output.write(CompatibleMessage.new("slow"))
		else
			metadata = call.request.headers["x-test"]&.first
			binary_metadata = call.request.headers["x-test-bin"]&.first
			binary_metadata = Base64.strict_decode64(binary_metadata) if binary_metadata
			output.write(CompatibleMessage.new([request.value, metadata, binary_metadata].compact.join(":")))
		end
	end
end

describe Async::GRPC::Compatible::ClientStub do
	include Sus::Fixtures::Async::HTTP::ServerContext
	
	let(:protocol) {Async::HTTP::Protocol::HTTP2}
	let(:service_name) {"compatible.Service"}
	let(:service) {CompatibleService.new(CompatibleInterface, service_name)}
	let(:app) {Async::GRPC::Dispatcher.new(services: {service_name => service})}
	let(:grpc_client) {Async::GRPC::Client.new(client)}
	let(:channel) {Async::GRPC::Compatible::Channel.new(client: grpc_client)}
	let(:stub) {subject.new("unused", nil, channel_override: channel)}
	
	def request(value, **options)
		stub.request_response(
			"/#{service_name}/Echo",
			CompatibleMessage.new(value),
			->(message){message.to_proto},
			CompatibleMessage.method(:decode),
			**options
		)
	end
	
	it "matches grpc-ruby's constructor call shape" do
		compatible_parameters = subject.instance_method(:initialize).parameters
		native_parameters = ::GRPC::ClientStub.instance_method(:initialize).parameters
		
		expect(compatible_parameters.map(&:first)).to be == native_parameters.map(&:first)
		expect(compatible_parameters.drop(2)).to be == native_parameters.drop(2)
	end
	
	it "matches grpc-ruby's unary call shape" do
		compatible_parameters = subject.instance_method(:request_response).parameters
		native_parameters = ::GRPC::ClientStub.instance_method(:request_response).parameters
		
		expect(compatible_parameters.map(&:first)).to be == native_parameters.map(&:first)
		expect(compatible_parameters.drop(4)).to be == native_parameters.drop(4)
	end
	
	it "performs a unary request" do
		response = request("Hello")
		
		expect(response).to be_a(CompatibleMessage)
		expect(response.value).to be == "Hello"
	end
	
	it "connects directly to a target" do
		direct_stub = subject.new(bound_url, :this_channel_is_insecure)
		response = direct_stub.request_response(
			"/#{service_name}/Echo",
			CompatibleMessage.new("direct"),
			->(message){message.to_proto},
			CompatibleMessage.method(:decode)
		)
		
		expect(response.value).to be == "direct"
	ensure
		direct_stub&.close
	end
	
	it "does not block sibling fibers" do
		client_stub = stub
		events = []
		parent = Async::Task.current
		
		slow = parent.async do
			client_stub.request_response(
				"/#{service_name}/Echo",
				CompatibleMessage.new("slow"),
				->(message){message.to_proto},
				CompatibleMessage.method(:decode)
			)
			events << :slow
		end
		fast = parent.async do
			client_stub.request_response(
				"/#{service_name}/Echo",
				CompatibleMessage.new("fast"),
				->(message){message.to_proto},
				CompatibleMessage.method(:decode)
			)
			events << :fast
		end
		
		fast.wait
		slow.wait
		
		expect(events).to be == [:fast, :slow]
	end
	
	it "normalizes method paths" do
		response = stub.request_response(
			"#{service_name}/Echo",
			CompatibleMessage.new("normalized"),
			->(message){message.to_proto},
			CompatibleMessage.method(:decode)
		)
		
		expect(response.value).to be == "normalized"
	end
	
	it "sends metadata" do
		response = request("Hello", metadata: {"x-test" => "metadata"})
		
		expect(response.value).to be == "Hello:metadata"
	end
	
	it "sends binary metadata" do
		response = request("Hello", metadata: {"x-test-bin" => "binary metadata"})
		
		expect(response.value).to be == "Hello:binary metadata"
	end
	
	it "raises grpc-ruby errors" do
		begin
			request("error")
		rescue ::GRPC::NotFound => error
			expect(error.message).to be =~ /Missing/
			expect(error.metadata).to be == {
				"x-error" => ["metadata"],
				"x-error-bin" => ["binary metadata"],
			}
		else
			expect(false).to be == true
		end
	end
	
	it "enforces deadlines" do
		expect do
			request("slow", deadline: Time.now + 0.01)
		end.to raise_exception(::GRPC::DeadlineExceeded)
	end
	
	it "enforces the default timeout" do
		timed_stub = subject.new("unused", nil, channel_override: channel, timeout: 0.01)
		
		expect do
			timed_stub.request_response(
				"/#{service_name}/Echo",
				CompatibleMessage.new("slow"),
				->(message){message.to_proto},
				CompatibleMessage.method(:decode)
			)
		end.to raise_exception(::GRPC::DeadlineExceeded)
	end
	
	it "supports grpc-ruby's infinite deadline" do
		response = request("infinite", deadline: ::GRPC::Core::TimeConsts::INFINITE_FUTURE)
		
		expect(response.value).to be == "infinite"
	end
	
	it "supports grpc-ruby's zero deadline" do
		expect do
			request("Hello", deadline: ::GRPC::Core::TimeConsts::ZERO)
		end.to raise_exception(::GRPC::DeadlineExceeded)
	end
	
	it "accepts a relative numeric deadline" do
		response = request("numeric", deadline: 1)
		
		expect(response.value).to be == "numeric"
	end
	
	it "rejects invalid deadlines" do
		expect do
			request("Hello", deadline: Object.new)
		end.to raise_exception(TypeError, message: be =~ /deadline/)
	end
	
	it "rejects expired deadlines before making the request" do
		expect do
			request("Hello", deadline: Time.now - 1)
		end.to raise_exception(::GRPC::DeadlineExceeded)
	end
	
	it "requires the marshaler to return bytes" do
		expect do
			stub.request_response(
				"/#{service_name}/Echo",
				CompatibleMessage.new("Hello"),
				->(_message){Object.new},
				CompatibleMessage.method(:decode)
			)
		end.to raise_exception(TypeError, message: be =~ /marshal/)
	end
	
	it "translates protocol errors into grpc-ruby errors" do
		failing_client = Object.new
		failing_client.define_singleton_method(:call) do |_request|
			raise Protocol::GRPC::Error.for(
				Protocol::GRPC::Status::INTERNAL,
				"Protocol failure",
				metadata: {"failure" => "true"}
			)
		end
		failing_channel = Async::GRPC::Compatible::Channel.new(client: failing_client)
		failing_stub = subject.new("unused", nil, channel_override: failing_channel)
		
		begin
			failing_stub.request_response(
				"/#{service_name}/Echo",
				CompatibleMessage.new("Hello"),
				->(message){message.to_proto},
				CompatibleMessage.method(:decode)
			)
		rescue ::GRPC::Internal => error
			expect(error.details).to be == "Protocol failure"
			expect(error.metadata).to be == {"failure" => "true"}
			expect(error.cause).to be_a(Protocol::GRPC::Error)
		else
			expect(false).to be == true
		end
	end
	
	it "rejects operation objects" do
		expect do
			request("Hello", return_op: true)
		end.to raise_exception(NotImplementedError, message: be =~ /return_op/)
	end
	
	it "rejects parent call propagation" do
		expect do
			request("Hello", parent: Object.new)
		end.to raise_exception(NotImplementedError, message: be =~ /parent/)
	end
	
	it "rejects per-call credentials" do
		expect do
			request("Hello", credentials: Object.new)
		end.to raise_exception(NotImplementedError, message: be =~ /credentials/)
	end
	
	it "rejects interceptors" do
		expect do
			subject.new("unused", nil, channel_override: channel, interceptors: [Object.new])
		end.to raise_exception(NotImplementedError, message: be =~ /interceptors/i)
	end
	
	with ".setup_channel" do
		it "reuses a compatible channel" do
			expect(subject.setup_channel(channel, "unused", nil)).to be == channel
		end
		
		it "wraps an existing Async client" do
			compatible_channel = subject.setup_channel(grpc_client, "unused", nil)
			
			expect(compatible_channel.client).to be == grpc_client
			expect(compatible_channel.endpoint).to be_nil
		end
		
		it "rejects native channel overrides" do
			expect do
				subject.setup_channel(Object.new, "unused", nil)
			end.to raise_exception(TypeError, message: be =~ /channel_override/)
		end
	end
	
	with ".endpoint_for" do
		it "constructs an insecure HTTP/2 endpoint" do
			endpoint = subject.endpoint_for("dns:///localhost:50051", :this_channel_is_insecure)
			
			expect(endpoint.to_url.to_s).to be == "http://localhost:50051/"
			expect(endpoint.protocol).to be == Async::HTTP::Protocol::HTTP2
		end
		
		it "normalizes two-slash DNS targets" do
			endpoint = subject.endpoint_for("dns://localhost:50051", :this_channel_is_insecure)
			
			expect(endpoint.to_url.to_s).to be == "http://localhost:50051/"
		end
		
		it "constructs a secure HTTP/2 endpoint" do
			credentials = ::GRPC::Core::ChannelCredentials.new
			endpoint = subject.endpoint_for("grpc.example.com:443", credentials)
			
			expect(endpoint.to_url.to_s).to be == "https://grpc.example.com/"
			expect(endpoint.protocol).to be == Async::HTTP::Protocol::HTTP2
		end
		
		it "rejects invalid credentials" do
			expect do
				subject.endpoint_for("localhost:50051", nil)
			end.to raise_exception(TypeError, message: be =~ /credentials/)
		end
		
		it "rejects unsupported target schemes" do
			expect do
				subject.endpoint_for("unix:///tmp/grpc.sock", :this_channel_is_insecure)
			end.to raise_exception(ArgumentError, message: be =~ /Unsupported/)
		end
	end
end
