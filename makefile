.PHONY: dev build-wasm

dev:
	git ls-files -cdmo --exclude-standard | entr -dr go run ./cmd/web

build-wasm:
	GOOS=js GOARCH=wasm tinygo build -o ./assets/wasm/wasm.wasm ./wasm/cfd/main.go
	cp `tinygo env TINYGOROOT`/targets/wasm_exec.js ./assets/wasm/
