module example.com/monorepo

go 1.26.0

require (
	github.com/acme/retry v1.0.0
	github.com/googleapis/gax-go v0.0.0-20161107002406-da06d194a00e
)

require (
	golang.org/x/net v0.59.0 // indirect
	golang.org/x/sys v0.48.0 // indirect
	golang.org/x/text v0.42.0 // indirect
	google.golang.org/genproto/googleapis/rpc v0.0.0-20260706201446-f0a921348800 // indirect
	google.golang.org/grpc v1.84.0 // indirect
	google.golang.org/protobuf v1.36.11 // indirect
)

// Libraries are copied into third_party/ by the import tool and built from there.
replace (
	github.com/acme/retry => ./third_party/acme-retry
	github.com/googleapis/gax-go => ./third_party/gax-go
)
