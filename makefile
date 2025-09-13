.PHONY: dev

dev:
	git ls-files -cdmo --exclude-standard | entr -d go run .
