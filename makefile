.PHONY: all bin/example bin/cli

all: bin/cli bin/example

bin/cli:
	go build -o ./bin/cli ./cmd/cli/main.go

bin/example:
	go build -o ./bin/example ./cmd/example/main.go
