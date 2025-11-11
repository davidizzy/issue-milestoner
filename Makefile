# Makefile for Issue-Milestoner

## help: Show Makefile targets. This is the default target.
.PHONY: help
help:
	@echo "Available targets:\n"
	@egrep '^## ' $(MAKEFILE_LIST) | column -t -s ':' | sed 's,^## ,,'

## quality-check: Run quality checks (linting, formatting, type checking).
.PHONY: quality-check
quality-check:
	@echo "Running quality checks..."
	@echo "Running shellcheck..."
	shellcheck --enable=all *.sh
	@echo "Running actionlint..."
	actionlint
	@echo "Running ratchet lint..."
	ratchet lint .github/workflows/*.yaml

## pin: Pin GitHub Action versions in workflow files.
.PHONY: pin
pin:
	ratchet pin .github/workflows/*.y*ml

## unpin: Unpin GitHub Action versions in workflow files.
.PHONY: unpin
unpin:
	ratchet unpin .github/workflows/*.y*ml