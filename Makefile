.PHONY: test install lint help

help:
	@echo "Crabterm Makefile"
	@echo ""
	@echo "Commands:"
	@echo "  make test        Run unit tests"
	@echo "  make install     Install crabterm to /usr/local/bin"
	@echo "  make lint        Run shellcheck"
	@echo ""

test:
	@chmod +x tests/run.sh
	@./tests/run.sh

install:
	@chmod +x src/crabterm
	@mkdir -p /usr/local/bin/lib
	@cp src/crabterm /usr/local/bin/crabterm
	@cp -r src/lib/* /usr/local/bin/lib/
	@ln -sf /usr/local/bin/crabterm /usr/local/bin/crab
	@echo "Installed crabterm to /usr/local/bin/"

lint:
	@if command -v shellcheck &>/dev/null; then \
		shellcheck src/crabterm src/lib/*.sh; \
		echo "Lint passed"; \
	else \
		echo "shellcheck not installed, skipping lint"; \
	fi
