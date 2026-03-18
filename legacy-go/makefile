.PHONY: all bin/example bin/cli

all: bin/cli bin/example bin/ghia

bin/cli cmd/cli:
	go build -o ./bin/cli ./cmd/cli

bin/example cmd/example:
	go build -o ./bin/example ./cmd/example

bin/ghia cmd/ghia:
	go build -o ./bin/ghia ./cmd/ghia
