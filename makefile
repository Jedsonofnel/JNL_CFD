.PHONY: build clean dev build-wasm clean-wasm build-prod clean-web-assets

build:
	go build -o ./bin/cli ./cmd/cli/main.go
	go build -o ./bin/web ./cmd/web/main.go
	go build -o ./bin/repl ./cmd/repl/main.go

build-prod: clean-web-assets build-wasm
	cd internal/web && go generate
	ENV=production go build -o ./bin/cli ./cmd/cli/main.go
	ENV=production go build -o ./bin/web ./cmd/web/main.go
	ENV=production go build -o ./bin/repl ./cmd/repl/main.go

clean: clean-web-assets
	rm -rf bin/*

clean-web-assets:
	rm -rf internal/web/templates internal/web/assets internal/web/assets.go \
		internal/web/jnlisp

dev:
	@echo "Starting development servers..."
	@$(MAKE) -j2 dev-server dev-wasm 2>&1 | sed 's/^/[DEV] /'

dev-server:
	@while true; do \
		echo "[SERVER] Starting Go server watcher..."; \
		git ls-files -cdmo --exclude-standard | grep -v '^wasm/' | entr -dr go run ./cmd/web; \
		sleep 1; \
	done

dev-wasm:
	@while true; do \
		echo "[WASM] Starting WASM watcher..."; \
		find wasm -name "*.go" | entr -dr $(MAKE) build-wasm-quiet; \
		sleep 1; \
	done

build-wasm-quiet: clean-wasm
	@echo "[WASM] Rebuilding..."
	@$(MAKE) build-wasm > /dev/null 2>&1 && echo "[WASM] Build complete!"

build-wasm: clean-wasm
	$(eval TIMESTAMP := $(shell date +%s))
	GOOS=js GOARCH=wasm tinygo build -o ./assets/wasm/cfd-$(TIMESTAMP).wasm \
		 ./wasm/cfd/main.go
	ln -sf cfd-$(TIMESTAMP).wasm ./assets/wasm/cfd-latest.wasm
	cp `tinygo env TINYGOROOT`/targets/wasm_exec.js ./assets/wasm/

clean-wasm:
	rm -rf ./assets/wasm/*.wasm
