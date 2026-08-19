# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "async/grpc/compatible"
require "async/grpc/compatible/tls_fixture"

describe Async::GRPC::Compatible::ChannelCredentials do
	let(:certificate_issuer) {Async::GRPC::Compatible::TLSFixture::CERTIFICATE_ISSUER}
	let(:client_authority) {Async::GRPC::Compatible::TLSFixture::CLIENT_AUTHORITY}
	let(:root_certificates) {certificate_issuer.certificate.to_pem}
	let(:private_key) {client_authority.key.to_pem}
	let(:certificate_chain) {client_authority.certificate.to_pem + root_certificates}
	
	it "translates grpc-ruby positional arguments into transport-neutral TLS configuration" do
		credentials = subject.new(root_certificates, private_key, certificate_chain)
		configuration = credentials.tls_configuration
		
		expect(configuration.trust_store.certificates).to be == [root_certificates.strip]
		expect(configuration.certificate_chain).to be == [
			client_authority.certificate.to_pem.strip,
			root_certificates.strip,
		]
		expect(configuration.private_key).to be == private_key
		expect(configuration.verification).to be == :peer
	end
	
	it "supports the default secure channel credential shape" do
		configuration = subject.new.tls_configuration
		
		expect(configuration.trust_store).to be_nil
		expect(configuration.certificate_chain).to be_nil
		expect(configuration.private_key).to be_nil
	end
	
	it "rejects an incomplete client identity" do
		expect do
			subject.new(root_certificates, private_key)
		end.to raise_exception(ArgumentError, message: be =~ /certificate chain and private key/i)
	end
	
	it "rejects an invalid certificate bundle" do
		expect do
			subject.new("not a certificate")
		end.to raise_exception(ArgumentError, message: be =~ /does not contain any certificates/i)
	end
end
