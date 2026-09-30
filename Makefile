SHELL := /bin/bash
WHITECHAIN_NETWORK ?= testnet
VALID_NETWORKS := mainnet testnet
JWT_FILE ?= keys/$(PROFILE)/jwt.txt
COMPOSE  ?= docker compose

# Node profile to operate on: full-snap-node | full-node | archive-node
PROFILE ?= full-snap-node
VALID_PROFILES := full-snap-node full-node archive-node

export WHITECHAIN_NETWORK
export PROFILE

.PHONY: help ensure-jwt check-env check-profile check-network \
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

ensure-jwt: check-profile
	@mkdir -p "$$(dirname "$(JWT_FILE)")"
	@if [ ! -s "$(JWT_FILE)" ]; then \
		openssl rand -hex 32 > "$(JWT_FILE)"; \
		chmod 600 "$(JWT_FILE)"; \
		echo "Generated $(JWT_FILE)"; \
	else \
		echo "Using existing $(JWT_FILE)"; \
	fi


check-env:
	@test -f .env || { echo "Missing .env. Copy .env.mainnet.example (or .env.testnet.example) to .env and fill values." >&2; exit 1; }
	@network=$$(sed -n 's/^[[:space:]]*WHITECHAIN_NETWORK[[:space:]]*=[[:space:]]*\([^[:space:]#]*\).*$$/\1/p' .env | tail -n 1 | tr -d '\042\047'); \
	test -n "$$network" || { echo "WHITECHAIN_NETWORK is not set in .env" >&2; exit 1; }; \
	for n in $(VALID_NETWORKS); do [ "$$network" = "$$n" ] && ok=1; done; \
	test -n "$$ok" || { echo "Invalid WHITECHAIN_NETWORK '$$network' in .env. Use one of: $(VALID_NETWORKS)" >&2; exit 1; }; \
	genesis="artifacts/$$network/genesis.json"; \
	rollup="artifacts/$$network/rollup.json"; \
	fix="re-copy it from the $$network/ directory of https://github.com/whitechain-labs/whitechain-bootstrap and verify its SHA-256"; \
	test -f "$$genesis" || { echo "Missing $$genesis – $$fix" >&2; exit 1; }; \
	test -f "$$rollup"  || { echo "Missing $$rollup – $$fix" >&2; exit 1; }; \
	command -v jq >/dev/null 2>&1 || { echo "jq not found: it is required to cross-check genesis.json against rollup.json" >&2; exit 1; }; \
	genesis_out=$$(jq -r '[(.config.chainId // ""), (.timestamp // "")] | @tsv' "$$genesis" 2>/dev/null); \
	lines=$$(printf '%s\n' "$$genesis_out" | grep -c .); \
	test "$$lines" = "1" || { echo "$$genesis is not a single valid JSON document (parsed $$lines) – $$fix" >&2; exit 1; }; \
	rollup_out=$$(jq -r '[(.l2_chain_id // ""), (.genesis.l2_time // ""), (.l1_chain_id // "")] | @tsv' "$$rollup" 2>/dev/null); \
	lines=$$(printf '%s\n' "$$rollup_out" | grep -c .); \
	test "$$lines" = "1" || { echo "$$rollup is not a single valid JSON document (parsed $$lines) – $$fix" >&2; exit 1; }; \
	genesis_chain_id=$$(printf '%s' "$$genesis_out" | cut -f1); \
	genesis_time=$$(printf '%s' "$$genesis_out" | cut -f2); \
	rollup_chain_id=$$(printf '%s' "$$rollup_out" | cut -f1); \
	rollup_time=$$(printf '%s' "$$rollup_out" | cut -f2); \
	rollup_l1_chain_id=$$(printf '%s' "$$rollup_out" | cut -f3); \
	case "$$genesis_chain_id" in ''|*[!0-9]*) echo "$$genesis: .config.chainId must be a decimal number, got '$$genesis_chain_id' – $$fix" >&2; exit 1 ;; esac; \
	case "$$rollup_chain_id"  in ''|*[!0-9]*) echo "$$rollup: .l2_chain_id must be a decimal number, got '$$rollup_chain_id' – $$fix" >&2; exit 1 ;; esac; \
	[ "$$genesis_chain_id" = "$$rollup_chain_id" ] || \
		{ echo "L2 chain ID mismatch: genesis=$$genesis_chain_id rollup=$$rollup_chain_id – the two files describe different chains" >&2; exit 1; }; \
	case "$$genesis_time" in \
		0[xX]*) hex=$${genesis_time#0[xX]}; \
			case "$$hex" in ''|*[!0-9a-fA-F]*) echo "$$genesis: .timestamp is not a valid hex number, got '$$genesis_time' – $$fix" >&2; exit 1 ;; esac; \
			genesis_time=$$((16#$$hex)) ;; \
		''|*[!0-9]*) echo "$$genesis: .timestamp must be a hex or decimal number, got '$$genesis_time' – $$fix" >&2; exit 1 ;; \
	esac; \
	case "$$rollup_time" in ''|*[!0-9]*) echo "$$rollup: .genesis.l2_time must be a decimal number, got '$$rollup_time' – $$fix" >&2; exit 1 ;; esac; \
	[ "$$genesis_time" = "$$rollup_time" ] || \
		{ echo "L2 genesis timestamp mismatch: genesis=$$genesis_time rollup=$$rollup_time – the two files are from different deployments of the same chain" >&2; exit 1; }; \
	case "$$rollup_l1_chain_id" in ''|*[!0-9]*) echo "$$rollup: .l1_chain_id must be a decimal number, got '$$rollup_l1_chain_id' – $$fix" >&2; exit 1 ;; esac; \
	case "$$network" in mainnet) expected_l1=1 ;; testnet) expected_l1=11155111 ;; *) expected_l1="$$rollup_l1_chain_id" ;; esac; \
	[ "$$rollup_l1_chain_id" = "$$expected_l1" ] || \
		{ echo "L1 chain ID mismatch for WHITECHAIN_NETWORK=$$network: rollup.json settles on L1 $$rollup_l1_chain_id, expected $$expected_l1 (mainnet: Ethereum mainnet 1, testnet: Sepolia 11155111)" >&2; exit 1; }

check-network:
	@for n in $(VALID_NETWORKS); do [ "$$WHITECHAIN_NETWORK" = "$$n" ] && exit 0; done; \
	echo "Invalid WHITECHAIN_NETWORK '$$WHITECHAIN_NETWORK'. Use one of: $(VALID_NETWORKS)" >&2; \
	exit 1

check-profile:
	@for p in $(VALID_PROFILES); do [ "$$PROFILE" = "$$p" ] && exit 0; done; \
	echo "Invalid PROFILE '$$PROFILE'. Use one of: $(VALID_PROFILES)" >&2; \
	exit 1

# ----------------------------
# Generic targets (PROFILE-driven)
# ----------------------------
up: check-profile check-network check-env ensure-jwt
	@$(COMPOSE) --profile "$$PROFILE" up -d

down: check-profile check-network
	@$(COMPOSE) --profile "$$PROFILE" down

reup: down up

ps: check-profile check-network
	@$(COMPOSE) --profile "$$PROFILE" ps

logs: check-profile check-network
	@$(COMPOSE) --profile "$$PROFILE" logs -f --tail=200

config: check-profile check-network
	@$(COMPOSE) --profile "$$PROFILE" config

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
