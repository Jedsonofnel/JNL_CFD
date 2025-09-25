.PHONY: build clean dev build-wasm clean-wasm

build:
	go build -o ./bin/cli ./cmd/cli/main.go
	go build -o ./bin/web ./cmd/web/main.go

clean:
	rm -rf bin/*

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
