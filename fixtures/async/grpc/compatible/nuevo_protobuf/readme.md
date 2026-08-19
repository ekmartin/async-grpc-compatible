# NuevoProtobuf fixture

The Ruby files in this directory were produced by NuevoProtobuf 2.5.4 from
`protos/compatible.proto` using its native gRPC client generator.

The integration test subclasses the generated client solely to provide the
explicit client stub injection point proposed for NuevoProtobuf. The generated
unary RPC method and generated message serialization are used unchanged.
