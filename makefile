.PHONY: dev

dev:
	git ls-files -cdmo --exclude-standard | entr -dr go run ./cmd/web
