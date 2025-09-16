.PHONY: dev build-wasm

dev:
	git ls-files -cdmo --exclude-standard | entr -dr go run ./cmd/web

clean-wasm:
	rm -rf ./assets/wasm/*.wasm

build-wasm: clean-wasm
	$(eval TIMESTAMP := $(shell date +%s))
	GOOS=js GOARCH=wasm tinygo build -o ./assets/wasm/cfd-$(TIMESTAMP).wasm \
		 ./wasm/cfd/main.go
	ln -sf cfd-$(TIMESTAMP).wasm ./assets/wasm/cfd-latest.wasm
	cp `tinygo env TINYGOROOT`/targets/wasm_exec.js ./assets/wasm/
