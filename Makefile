SHELL := /bin/bash
WHITECHAIN_NETWORK ?= testnet
JWT_FILE ?= keys/jwt.txt
COMPOSE  ?= docker compose

# Node profile to operate on: full-snap-node | full-node | archive-node
PROFILE ?= full-snap-node

export WHITECHAIN_NETWORK

.PHONY: help ensure-jwt check-env \
        up down reup ps logs config \
        up-full-snap-node down-full-snap-node reup-full-snap-node ps-full-snap-node logs-full-snap-node \
        up-full-node down-full-node reup-full-node ps-full-node logs-full-node \
        up-archive-node down-archive-node reup-archive-node ps-archive-node logs-archive-node

help:
	@echo "Node profiles: full-snap-node | full-node | archive-node"
	@echo ""
	@echo "  full-snap-node  Pruned public RPC node, execution-layer sync (snap from a trusted reth peer) – fastest, simplest"
	@echo "  full-node       Pruned public RPC node, consensus-layer sync (re-executes from L1)"
	@echo "  archive-node    Archive public RPC node, consensus-layer sync (re-executes from L1)"
	@echo ""
	@echo "Per-profile targets (full-snap-node / full-node / archive-node):"
	@echo "  make up-full-snap-node   Start the snap-sync full / pruned public RPC node"
	@echo "  make up-full-node        Start the full / pruned public RPC node"
	@echo "  make up-archive-node     Start the archive public RPC node"
	@echo "  make down-<profile>      Stop the chosen node"
	@echo "  make reup-<profile>      Down + up the chosen node"
	@echo "  make ps-<profile>        Show service status"
	@echo "  make logs-<profile>      Tail logs"
	@echo ""
	@echo "Generic targets (use PROFILE=<profile>, default: $(PROFILE)):"
	@echo "  make up PROFILE=archive-node"
	@echo "  make down PROFILE=archive-node"
	@echo "  make reup | ps | logs | config"
	@echo ""
	@echo "  make ensure-jwt       Generate keys/jwt.txt if missing"

ensure-jwt:
	@mkdir -p keys
	@if [ ! -s "$(JWT_FILE)" ]; then \
		openssl rand -hex 32 > "$(JWT_FILE)"; \
		chmod 600 "$(JWT_FILE)"; \
		echo "Generated $(JWT_FILE)"; \
	else \
		echo "Using existing $(JWT_FILE)"; \
	fi

check-env:
	@test -f .env || (echo "Missing .env. Copy .env.mainnet.example (or .env.testnet.example) to .env and fill values." && exit 1)
	@set -a; . ./.env; set +a; \
	test -f "artifacts/$$WHITECHAIN_NETWORK/genesis.json" || (echo "Missing artifacts/$$WHITECHAIN_NETWORK/genesis.json" && exit 1); \
	test -f "artifacts/$$WHITECHAIN_NETWORK/rollup.json"  || (echo "Missing artifacts/$$WHITECHAIN_NETWORK/rollup.json"  && exit 1)

# ----------------------------
# Generic targets (PROFILE-driven)
# ----------------------------
up: check-env ensure-jwt
	@$(COMPOSE) --profile $(PROFILE) up -d

down:
	@$(COMPOSE) --profile $(PROFILE) down

reup: down up

ps:
	@$(COMPOSE) --profile $(PROFILE) ps

logs:
	@$(COMPOSE) --profile $(PROFILE) logs -f --tail=200

config:
	@$(COMPOSE) --profile $(PROFILE) config

# ----------------------------
# FULL SNAP NODE (pruned, execution-layer / snap sync)
# ----------------------------
up-full-snap-node:
	@$(MAKE) up PROFILE=full-snap-node

down-full-snap-node:
	@$(MAKE) down PROFILE=full-snap-node

reup-full-snap-node:
	@$(MAKE) reup PROFILE=full-snap-node

ps-full-snap-node:
	@$(MAKE) ps PROFILE=full-snap-node

logs-full-snap-node:
	@$(MAKE) logs PROFILE=full-snap-node

# ----------------------------
# FULL NODE (pruned, consensus-layer sync)
# ----------------------------
up-full-node:
	@$(MAKE) up PROFILE=full-node

down-full-node:
	@$(MAKE) down PROFILE=full-node

reup-full-node:
	@$(MAKE) reup PROFILE=full-node

ps-full-node:
	@$(MAKE) ps PROFILE=full-node

logs-full-node:
	@$(MAKE) logs PROFILE=full-node

# ----------------------------
# ARCHIVE NODE (full history, consensus-layer sync)
# ----------------------------
up-archive-node:
	@$(MAKE) up PROFILE=archive-node

down-archive-node:
	@$(MAKE) down PROFILE=archive-node

reup-archive-node:
	@$(MAKE) reup PROFILE=archive-node

ps-archive-node:
	@$(MAKE) ps PROFILE=archive-node

logs-archive-node:
	@$(MAKE) logs PROFILE=archive-node
