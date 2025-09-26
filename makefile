.PHONY: build clean dev build-wasm clean-wasm build-prod clean-web-assets

build:
	go build -o ./bin/cli ./cmd/cli/main.go
	go build -o ./bin/web ./cmd/web/main.go
	go build -o ./bin/repl ./cmd/repl/main.go

build-prod: clean-web-assets
	cd internal/web && go generate
	ENV=production go build -o ./bin/cli ./cmd/cli/main.go
	ENV=production go build -o ./bin/web ./cmd/web/main.go
	ENV=production go build -o ./bin/repl ./cmd/repl/main.go

clean: clean-web-assets
	rm -rf bin/*

clean-web-assets:
	rm -rf internal/web/templates internal/web/assets internal/web/assets.go

dev:
	git ls-files -cdmo --exclude-standard | entr -dr go run ./cmd/web

build-wasm: clean-wasm
	$(eval TIMESTAMP := $(shell date +%s))
	GOOS=js GOARCH=wasm tinygo build -o ./assets/wasm/cfd-$(TIMESTAMP).wasm \
		 ./wasm/cfd/main.go
	ln -sf cfd-$(TIMESTAMP).wasm ./assets/wasm/cfd-latest.wasm
	cp `tinygo env TINYGOROOT`/targets/wasm_exec.js ./assets/wasm/

clean-wasm:
	rm -rf ./assets/wasm/*.wasm
