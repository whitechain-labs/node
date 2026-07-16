# Whitechain Public RPC Node

Standalone Docker Compose stack for running an external Whitechain RPC node. The node follows the canonical Whitechain L2 chain over L1 derivation plus P2P, and forwards user transactions to the Whitechain network.

Each node is a pair of services:

- `op-reth` – execution client, exposes JSON-RPC and WebSocket
- `op-node` – consensus client, derives the chain from L1 and peers over libp2p

## Concepts: storage vs sync method

Two independent choices define a node. The profiles below are fixed combinations of them.

**Storage** – how much state op-reth keeps:

- **Pruned** (`--full`) – keeps only recent state, prunes history. Smallest disk. Serves a complete public RPC for current data.
- **Archive** (no `--full`) – keeps the full historical state. Largest disk. Required for historical tracing and `eth_call` at old blocks.

**Sync method** – how op-reth obtains state:

- **consensus-layer** (op-node default) – op-node derives the chain from L1 and feeds blocks to op-reth one by one; op-reth **re-executes every transaction** from genesis. No EL P2P peer needed, but the initial sync is **long** unless you restore a DB snapshot.
- **execution-layer** (`--syncmode=execution-layer`, "snap") – op-node only drives the head; op-reth **snap-syncs the state snapshot** directly from a trusted reth peer over EL P2P. Fast, no snapshot restore needed, but requires a reachable seed peer (`WHITECHAIN_RETH_TRUSTED_PEERS`). Snap sync cannot build an archive – it only produces pruned state.

| Storage | consensus-layer (re-execute) | execution-layer (snap) |
| --- | --- | --- |
| Pruned (`--full`) | `full-node` | `full-snap-node` |
| Archive | `archive-node` | not supported (snap can't build history) |

## Node profiles

The stack ships three profiles. You pick one with the `PROFILE` variable (or a per-profile `make` target):

| Profile | Purpose | Storage | Sync method | DB snapshot | Public RPC |
| --- | --- | --- | --- | --- | --- |
| `full-snap-node` | Recommended default – fastest, simplest bootstrap | Pruned (`--full`) | execution-layer (snap) | Not needed | Yes |
| `full-node` | Public RPC node without snap sync | Pruned (`--full`) | consensus-layer | Recommended | Yes |
| `archive-node` | Full historical state + tracing | Archive (full history) | consensus-layer | Recommended | Yes |

- **full-snap-node** – the recommended default and fastest, simplest way to bring up a node. Pruned execution state, basic RPC namespaces (`eth,net,web3,rpc`). Bootstraps by snap-syncing from a trusted reth peer (`WHITECHAIN_RETH_TRUSTED_PEERS`) instead of re-executing, so it needs no DB snapshot. Use it when you have a reachable seed reth enode (your own fleet, or one the Whitechain team provides).
- **full-node** – same pruned state and namespaces as `full-snap-node`, but syncs in consensus-layer mode by re-executing the chain from L1. Use it when you have no trusted reth peer to snap-sync from. Restore a DB snapshot to avoid a long initial sync.
- **archive-node** – keeps the full historical state and enables `debug`, `trace`, `txpool`, `reth` namespaces plus higher RPC limits. Use it for explorers, indexers, and historical `eth_call`/`debug_traceTransaction`. Syncs by re-executing from L1 (archive cannot snap-sync), so restore a DB snapshot to avoid a very long initial sync. Needs the most disk and RAM.

## Database snapshots (skip the long initial sync)

This applies to the **non-snap** profiles (`full-node` and `archive-node`). They sync in consensus-layer mode, which means op-node derives the chain from L1 and op-reth **re-executes every transaction from genesis**. On a long-running chain that takes many hours. Restoring a published `op-reth` DB snapshot lets you start near a recent block and only sync the gap since the snapshot was taken.

> `full-snap-node` does **not** need a snapshot – it snap-syncs the state directly from `WHITECHAIN_RETH_TRUSTED_PEERS`.

The workflow:

1. Stop the node if it is running:

   ```bash
   make down PROFILE=full-node
   ```

2. Download the published snapshot archive for your network and profile (URL provided by the Whitechain team), then extract it into the matching data directory. The archive contains the `op-reth` `db`, `static_files`, and related folders:

   ```bash
   # example layout – adjust the URL to the one the team gives you
   mkdir -p data/full-node/op-reth
   curl -L "<WHITECHAIN_SNAPSHOT_URL>/op-reth-mainnet-full.tar.zst" \
     | zstd -d \
     | tar -x -C data/full-node/op-reth
   ```

   The result must be `data/full-node/op-reth/db`, `data/full-node/op-reth/static_files`, etc. (see [Data layout](#data-layout)).

3. Start the node. op-node derives the remaining blocks from L1 and catches up the unsafe head over P2P:

   ```bash
   make up PROFILE=full-node
   make logs PROFILE=full-node
   ```

Notes:

- Match the snapshot to the **same profile**. A pruned snapshot cannot serve archive queries; restore an archive snapshot into `data/archive-node/op-reth` for an archive node.
- Restore only the `op-reth` data. The `op-node` directory (`peerstore`, `discovery`, `safedb`) is rebuilt automatically and does not need to be restored.
- The snapshot is only a starting point. The node still needs a working L1 RPC + Beacon to derive everything after the snapshot block.
- Without a snapshot, `full-node` and `archive-node` sync from genesis by re-executing every transaction – expect a long initial sync.

## Requirements

- Docker with Compose v2
- Your own Ethereum L1 RPC endpoint
- Your own Ethereum L1 Beacon endpoint
- The published `genesis.json` and `rollup.json` for the chosen network, under `artifacts/<network>/`
- A reachable public IP for the node (`PUBLIC_IP`), used for P2P advertisement
- For `full-snap-node`: a trusted reth enode to snap-sync from (`WHITECHAIN_RETH_TRUSTED_PEERS`)
- `make`, `git`, `openssl`, `curl`; `zstd` and `tar` if you restore from a snapshot

| Whitechain network | L1 chain |
| --- | --- |
| Whitechain mainnet | Ethereum mainnet |
| Whitechain testnet | Ethereum Sepolia |

### Hardware

| Component | full-snap-node / full-node | archive-node |
| --- | --- | --- |
| CPU | 4+ cores | 8+ cores |
| RAM | 16 GB | 32 GB |
| Storage | NVMe SSD, 500 GB min / 1 TB recommended (≥ 2× current chain size + 20%) | NVMe SSD, sized for full history (≥ 1 TB) |
| Network | 100 Mbps+ | 1 Gbps |

## Quick Start

1. Place the published artifacts under `artifacts/<network>/`:

   ```
   artifacts/mainnet/genesis.json
   artifacts/mainnet/rollup.json
   ```

   The folder name must match `WHITECHAIN_NETWORK` in `.env`. For testnet use `artifacts/testnet/`.

2. Create your `.env`:

   ```bash
   cp .env.mainnet.example .env   # or .env.testnet.example
   ```

   Fill in at least `PUBLIC_IP`, `WHITECHAIN_PUBLIC_RPC`, `L1_RPC_URL`, `L1_BEACON_URL` (see [Configuration](#configuration)). For `full-snap-node` also set `WHITECHAIN_RETH_TRUSTED_PEERS`.

3. (Recommended for `full-node` / `archive-node`) Restore an `op-reth` snapshot to skip the long initial sync – see [Database snapshots](#database-snapshots-skip-the-long-initial-sync).

4. Start the node profile you want:

   ```bash
   make up-full-snap-node   # recommended default: pruned node, snap-syncs from a trusted peer
   # make up-full-node      # pruned node, consensus-layer sync (re-executes from L1)
   # make up-archive-node   # archive node

   make logs-full-snap-node
   ```

   `make up` validates `.env` and the artifacts, generates `keys/jwt.txt` if missing, then runs `docker compose --profile <profile> up -d`.

5. Confirm the node responds (use the profile's HTTP port):

   ```bash
   curl -s -X POST http://127.0.0.1:8545 \
     -H 'Content-Type: application/json' \
     --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'
   ```

## Configuration

Required `.env` variables:

| Variable | Description |
| --- | --- |
| `WHITECHAIN_NETWORK` | Subdirectory under `artifacts/`, e.g. `mainnet` or `testnet` |
| `PUBLIC_IP` | Public IP of this host, advertised for op-reth and op-node P2P |
| `WHITECHAIN_PUBLIC_RPC` | Public Whitechain RPC, used as `--rollup.sequencer-http` for op-reth (transaction forwarding) |
| `L1_RPC_URL` | Operator-provided Ethereum L1 RPC endpoint |
| `L1_BEACON_URL` | Operator-provided Ethereum L1 Beacon endpoint |

`full-snap-node` profile additionally requires:

| Variable | Description |
| --- | --- |
| `WHITECHAIN_RETH_TRUSTED_PEERS` | Trusted reth enode to snap-sync from, in the form `enode://<pubkey>@<ip>:30303` |

Optional variables (with defaults):

| Variable | Default | Description |
| --- | --- | --- |
| `L1_RPC_KIND` | `basic` | One of `alchemy`, `quicknode`, `infura`, `parity`, `nethermind`, `debug_geth`, `erigon`, `standard`, `any` if your provider supports extra receipt methods |
| `WHITECHAIN_PUBLIC_OP_NODE_P2P` | empty | Static op-node peer multiaddr `/dns4/<host>/tcp/9222/p2p/<peerID>` |
| `OP_NODE_ONLY_REQ_TO_STATIC` | `false` | Restrict unsafe-block requests to the static peer only |
| `OP_RETH_IMAGE` | `op-reth:v2.0.0` | Pin the op-reth image |
| `OP_NODE_IMAGE` | `op-node:v1.19.0` | Pin the op-node image |

Archive-only RPC limits (optional):

| Variable | Default |
| --- | --- |
| `RPC_MAX_CONNECTIONS` | `1000` |
| `RPC_MAX_LOGS_PER_RESPONSE` | `20000` |
| `RPC_MAX_BLOCKS_PER_FILTER` | `100000` |
| `RPC_MAX_TRACING_REQUESTS` | `8` |

Host port overrides – see [Ports](#ports).

## Ports

Only one profile runs at a time, so all profiles share the same host ports. Each is overridable through the env var in parentheses.

| Port | Default | Env var |
| --- | --- | --- |
| HTTP RPC | `8545` | `HOST_HTTP_PORT` |
| WebSocket RPC | `8546` | `HOST_WS_PORT` |
| op-node RPC | `9545` (loopback `127.0.0.1` only) | `HOST_OP_NODE_RPC_PORT` |
| op-node P2P (TCP+UDP) | `9222` | `HOST_OP_NODE_P2P_PORT` |
| EL P2P (TCP+UDP) | `30303` (disabled by default) | `HOST_EL_P2P_PORT` |

- The Engine API (`8551`) stays inside the compose network and is not published to the host.
- op-node RPC (`9545`) is bound to loopback (`127.0.0.1`) only – reachable for local monitoring on the host, never from the network. The `admin` namespace is not enabled, so it serves only the read-only `optimism`, `opp2p`, and `superroot` namespaces.
- The EL P2P port (`30303`) is **not** published by default – snap sync only needs outbound connectivity to the trusted peer. Its host mapping is commented out in `docker-compose.yml`; uncomment it only if you want inbound EL peering.
- Only the public JSON-RPC (`8545`) and WebSocket (`8546`) ports are network-facing, and they expose only read-only namespaces. Still, put them behind a firewall, reverse proxy, or rate limiter before serving untrusted clients.
- Run only one profile at a time – they all bind the same host ports. To run two side by side on one host, override one profile's ports in `.env`.

## Data layout

Each profile keeps its data in its own subtree, so profiles never clash:

```
data/
  full-snap-node/
    op-reth/    # execution db, static_files, blobstore, ...
    op-node/    # peerstore, discovery, safedb
  full-node/
    op-reth/
    op-node/
  archive-node/
    op-reth/
    op-node/
```

Snapshots are restored into `data/<profile>/op-reth/`.

## Operations

The generic targets take `PROFILE=full-snap-node|full-node|archive-node` (default `full-snap-node`):

```bash
make up PROFILE=archive-node     # start
make down PROFILE=archive-node   # stop
make reup PROFILE=archive-node   # down + up
make ps PROFILE=archive-node     # status
make logs PROFILE=archive-node   # tail logs
make config PROFILE=archive-node # render merged compose config
```

Per-profile shortcuts:

```bash
make up-full-snap-node   make down-full-snap-node   make reup-full-snap-node   make ps-full-snap-node   make logs-full-snap-node
make up-full-node        make down-full-node        make reup-full-node        make ps-full-node        make logs-full-node
make up-archive-node     make down-archive-node     make reup-archive-node     make ps-archive-node     make logs-archive-node

make ensure-jwt    # generate keys/jwt.txt if missing
make help          # list all targets
```

## Health checks

Execution client (use the profile's HTTP port):

```bash
curl -s -X POST http://127.0.0.1:8545 \
  -H 'Content-Type: application/json' \
  --data '{"jsonrpc":"2.0","method":"eth_getBlockByNumber","params":["latest",false]}'
```

op-node sync status (op-node RPC on loopback `9545`, run on the host):

```bash
curl -s -X POST http://127.0.0.1:9545 \
  -H 'Content-Type: application/json' \
  --data '{"jsonrpc":"2.0","method":"optimism_syncStatus","params":[],"id":1}'
```

## Sending transactions

Applications submit transactions to the local `op-reth` HTTP port. The node forwards them to `WHITECHAIN_PUBLIC_RPC`, which routes them to the closed sequencer. You need no direct access to the sequencer.

```bash
curl -s -X POST http://127.0.0.1:8545 \
  -H 'Content-Type: application/json' \
  --data '{"jsonrpc":"2.0","method":"eth_sendRawTransaction","params":["0x..."],"id":1}'
```

## Available RPC namespaces

- `full-snap-node` / `full-node` op-reth HTTP/WS: `eth`, `net`, `web3`, `rpc`
- `archive-node` op-reth HTTP: `eth`, `net`, `web3`, `rpc`, `debug`, `trace`, `txpool`, `reth`; WS: `eth`, `net`, `web3`, `rpc`
- op-reth exposes no `admin` namespace on any profile – all exposed namespaces are read-only.
- op-node RPC (`9545`, loopback-only): `optimism`, `opp2p`, `superroot` (the `admin` namespace is not enabled). `superroot` is a read-only OP Stack interop API (`superroot_getSuperRootAtTimestamp`) that op-node registers unconditionally; it cannot be disabled and is unused in this single-chain deployment.

## Updating the node

Image versions are pinned in `docker-compose.yml`. To upgrade:

```bash
git pull
docker compose pull
make reup PROFILE=full-snap-node
```

If the upgrade includes a new hardfork, replace `artifacts/<network>/rollup.json` (and `genesis.json` if it changed) with the published version before `make reup`. Apply hardfork artifacts before the activation timestamp to avoid a chain-divergence stall.

## Notes

- This stack holds no project-side private keys. The sequencer, batcher, proposer, and challenger keys stay on the Whitechain side. You operate a follow-only node.
- The Engine API on `8551` is bound only to the internal compose network. Do not publish it.
- op-node RPC (`9545`) is bound to loopback only and does not enable the `admin` namespace. op-reth exposes no `admin` namespace. The node therefore exposes no administrative or state-mutating control surface to the network.
- `keys/jwt.txt` is generated locally and used only between op-node and op-reth in this stack. It does not need to match anything outside.
- To resync a profile from scratch: `make down PROFILE=<p>`, then `rm -rf data/<p>/op-reth data/<p>/op-node`, then `make up PROFILE=<p>`. For `full-node`/`archive-node` prefer restoring a snapshot over a full genesis resync.
