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

- **consensus-layer** (op-node default) – op-node derives the chain from L1 and feeds blocks to op-reth one by one; op-reth **re-executes every transaction** from genesis. No EL P2P peer needed, but the initial sync is **long** on a chain with history behind it.
- **execution-layer** (`--syncmode=execution-layer`, "snap") – op-node only drives the head; op-reth **snap-syncs the state** directly from a trusted reth peer over EL P2P. Fast, but requires a reachable seed peer (`WHITECHAIN_RETH_TRUSTED_PEERS`). Snap sync cannot build an archive – it only produces pruned state.

| Storage | consensus-layer (re-execute) | execution-layer (snap) |
| --- | --- | --- |
| Pruned (`--full`) | `full-node` | `full-snap-node` |
| Archive | `archive-node` | not supported (snap can't build history) |

## Node profiles

The stack ships three profiles. You pick one with the `PROFILE` variable (or a per-profile `make` target):

| Profile | Purpose | Storage | Sync method | Initial sync | Public RPC |
| --- | --- | --- | --- | --- | --- |
| `full-snap-node` | Recommended default – fastest, simplest bootstrap | Pruned (`--full`) | execution-layer (snap) | Fast | Yes |
| `full-node` | Public RPC node without snap sync | Pruned (`--full`) | consensus-layer | Long – re-executes from genesis | Yes |
| `archive-node` | Full historical state, tracing on opt-in | Archive (full history) | consensus-layer | Longest – re-executes from genesis | Yes |

- **full-snap-node** – the recommended default and fastest, simplest way to bring up a node. Pruned execution state, basic RPC namespaces (`eth,net,web3,rpc`). Bootstraps by snap-syncing from a trusted reth peer (`WHITECHAIN_RETH_TRUSTED_PEERS`) instead of re-executing. Use it when you have a reachable seed reth enode (your own fleet, or one the Whitechain team provides).
- **full-node** – same pruned state and namespaces as `full-snap-node`, but syncs in consensus-layer mode by re-executing the chain from L1. Use it when you have no trusted reth peer to snap-sync from. Expect a long initial sync on a chain with history behind it.
- **archive-node** – keeps the full historical state and raises the RPC limits. Use it for explorers, indexers, and historical `eth_call`/`debug_traceTransaction`. Its RPC namespaces are the same read-only default as the other profiles (`HTTP_API` / `WS_API` = `eth,net,web3,rpc`); `debug`, `trace`, `txpool`, `reth` are an explicit opt-in through those variables – see [Available RPC namespaces](#available-rpc-namespaces). Syncs by re-executing from L1 (archive cannot snap-sync), so its initial sync is the longest of the three. Needs the most disk and RAM.

## Requirements

- Docker with Compose v2
- Your own Ethereum L1 RPC endpoint
- Your own Ethereum L1 Beacon endpoint
- The published `genesis.json` and `rollup.json` for the chosen network, from [whitechain-bootstrap](https://github.com/whitechain-labs/whitechain-bootstrap), placed under `artifacts/<network>/`
- A reachable public IP for the node (`PUBLIC_IP`), used for P2P advertisement
- For `full-snap-node`: a trusted reth enode to snap-sync from (`WHITECHAIN_RETH_TRUSTED_PEERS`)
- `make`, `git`, `openssl`, `curl`

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

1. Get the network artifacts and place them under `artifacts/<network>/`. They are not shipped in this repository – the authoritative copy is the [whitechain-bootstrap](https://github.com/whitechain-labs/whitechain-bootstrap) repository, also described under [Network artifacts](https://docs.whitechain.io/operate/run-a-node/network-artifacts) in the Whitechain docs:

   ```bash
   git clone https://github.com/whitechain-labs/whitechain-bootstrap.git
   cd whitechain-bootstrap

   # verify the files against the SHA-256 hashes published in that
   # repository's README (and on the docs page) before using them
   shasum -a 256 testnet/genesis.json testnet/rollup.json

   cp testnet/genesis.json testnet/rollup.json <this-repo>/artifacts/testnet/
   ```

   The result must be:

   ```
   artifacts/testnet/genesis.json
   artifacts/testnet/rollup.json
   ```

   The folder name must match `WHITECHAIN_NETWORK` in `.env` (`mainnet` or `testnet`). Compare the hashes yourself – this repository deliberately keeps no copy of the artifacts and no checksum file of its own, so there is a single source of truth to check against.

2. Create your `.env`:

   ```bash
   cp .env.mainnet.example .env   # or .env.testnet.example
   ```

   Fill in at least `PUBLIC_IP`, `WHITECHAIN_PUBLIC_RPC`, `L1_RPC_URL`, `L1_BEACON_URL` (see [Configuration](#configuration)). For `full-snap-node` also set `WHITECHAIN_RETH_TRUSTED_PEERS`.

3. Start the node profile you want:

   ```bash
   make up-full-snap-node   # recommended default: pruned node, snap-syncs from a trusted peer
   # make up-full-node      # pruned node, consensus-layer sync (re-executes from L1)
   # make up-archive-node   # archive node

   make logs-full-snap-node
   ```

   `make up` validates `.env` and the artifacts, generates `keys/<profile>/jwt.txt` if missing, then runs `docker compose --profile <profile> up -d`.

4. Confirm the node responds (use the profile's HTTP port):

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
| `HTTP_API` | `eth,net,web3,rpc` | op-reth HTTP (`8545`) RPC namespaces, same variable for all three profiles. Comma-separated, no spaces. See [Available RPC namespaces](#available-rpc-namespaces) before adding `debug`, `trace`, `txpool`, `reth` |
| `WS_API` | `eth,net,web3,rpc` | op-reth WebSocket (`8546`) RPC namespaces, same variable for all three profiles. Same rules as `HTTP_API` |
| `L1_RPC_KIND` | `basic` | One of `alchemy`, `quicknode`, `infura`, `parity`, `nethermind`, `debug_geth`, `erigon`, `standard`, `any` if your provider supports extra receipt methods |
| `WHITECHAIN_PUBLIC_OP_NODE_P2P` | empty | Static op-node peer multiaddr `/dns4/<host>/tcp/9222/p2p/<peerID>` |
| `OP_NODE_ONLY_REQ_TO_STATIC` | `false` | Restrict unsafe-block requests to the static peer only |
| `OP_RETH_IMAGE` | `public.ecr.aws/l8q8a0h5/op-reth:v2.3.3` | Pin the op-reth image |
| `OP_NODE_IMAGE` | `public.ecr.aws/l8q8a0h5/op-node:v1.19.3` | Pin the op-node image |

Archive-only RPC limits (optional):

| Variable | Default |
| --- | --- |
| `RPC_MAX_CONNECTIONS` | `1000` |
| `RPC_MAX_LOGS_PER_RESPONSE` | `20000` |
| `RPC_MAX_BLOCKS_PER_FILTER` | `100000` |
| `RPC_MAX_TRACING_REQUESTS` | `8` |

`RPC_MAX_TRACING_REQUESTS` caps how many tracing calls run at once; it does not cap the cost of a single call. It only matters once `debug`/`trace` are enabled through `HTTP_API` or `WS_API`.

Host port overrides – see [Ports](#ports).

## Ports

Only one profile runs at a time, so all profiles share the same host ports. Each is overridable through the env var in parentheses.

| Port | Default | Env var |
| --- | --- | --- |
| HTTP RPC | `8545` | `HOST_HTTP_PORT` |
| WebSocket RPC | `8546` | `HOST_WS_PORT` |
| op-node RPC | `9545` (loopback `127.0.0.1` only) | `HOST_OP_NODE_RPC_PORT` |
| op-node P2P (TCP+UDP) | `9222` | `HOST_OP_NODE_P2P_PORT` |
| EL P2P (TCP+UDP) | `30303` – published on `full-snap-node`, not published on `full-node` / `archive-node` | `HOST_EL_P2P_PORT` |

- The Engine API (`8551`) stays inside the compose network and is not published to the host.
- op-node RPC (`9545`) is bound to loopback (`127.0.0.1`) only – reachable for local monitoring on the host, never from the network. The `admin` namespace is not enabled, so it serves only the read-only `optimism`, `opp2p`, and `superroot` namespaces.
- The EL P2P port (`30303`) is published **only by the `full-snap-node` profile** – the recommended default – on all interfaces (`0.0.0.0`), TCP and UDP. That profile bootstraps over EL P2P: op-reth snap-syncs the state from the trusted reth peer and uses reth discovery (UDP `30303`) and devp2p (TCP `30303`) for it, so the port is reachable for inbound EL peers as well. The upstream OP Stack compose example publishes the same port the same way. It carries devp2p traffic only – no RPC, no `admin` surface – but if you do not want inbound EL peering, remap it with `HOST_EL_P2P_PORT` or block it at the firewall.
- For `full-node` and `archive-node` the `30303` mapping is commented out in `docker-compose.yml` and the port is **not** published: both sync in consensus-layer mode, deriving the chain from L1, and need no EL peering. Uncomment it only if you want inbound EL peers on those profiles.
- Of the RPC surfaces, only the public JSON-RPC (`8545`) and WebSocket (`8546`) ports are network-facing, and they expose only read-only namespaces. Still, put them behind a firewall, reverse proxy, or rate limiter before serving untrusted clients.
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
keys/
  full-snap-node/jwt.txt
  full-node/jwt.txt
  archive-node/jwt.txt
```

Each profile also owns its Engine API secret in `keys/<profile>/jwt.txt` and its own Compose network (`public_rpc_full_snap`, `public_rpc_full`, `public_rpc_archive`), so two profiles running at the same time share neither a credential nor a network path. `make up` generates the secret for the selected profile if it is missing.

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

make ensure-jwt    # generate keys/<profile>/jwt.txt if missing
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

- op-reth HTTP (`8545`), all three profiles: `HTTP_API` from `.env`, default `eth,net,web3,rpc`.
- op-reth WS (`8546`), all three profiles: `WS_API` from `.env`, default `eth,net,web3,rpc`.
- Both variables drive every profile – `archive-node` included – so an archive node serves the same read-only set as the others unless you widen it deliberately. The two ports are configured independently: widening `HTTP_API` does not change WS, and the reverse.
- `debug`, `trace`, `txpool`, `reth` are an explicit opt-in: add them to `HTTP_API` (and to `WS_API` only if you also need them over WebSocket), for example `HTTP_API=eth,net,web3,rpc,debug,trace,txpool,reth`. Only meaningful on `archive-node`, which has the history these methods read. The stack ships no authentication, CORS or vhost restriction on `8545`/`8546`, and `RPC_MAX_TRACING_REQUESTS` bounds concurrency, not the cost of one call – a single `trace_block` or `debug_traceTransaction` on a heavy block costs seconds of CPU and gigabytes of RAM. Enable them only behind a reverse proxy that allowlists methods and rate-limits clients (Whitechain runs `proxyd` in front of its own public RPC), never on a port open to untrusted clients.
- op-reth exposes no `admin` namespace on any profile – all exposed namespaces are read-only.
- op-node RPC (`9545`, loopback-only): `optimism`, `opp2p`, `superroot` (the `admin` namespace is not enabled). `superroot` is a read-only OP Stack interop API (`superroot_getSuperRootAtTimestamp`) that op-node registers unconditionally; it cannot be disabled and is unused in this single-chain deployment.

## Updating the node

Image versions are pinned in `docker-compose.yml`. To upgrade:

```bash
git pull
docker compose pull
make reup PROFILE=full-snap-node
```

If the upgrade includes a new hardfork, pull the new `rollup.json` (and `genesis.json` if it changed) from [whitechain-bootstrap](https://github.com/whitechain-labs/whitechain-bootstrap), check it against the SHA-256 hashes published there, copy it into `artifacts/<network>/`, then `make reup`. The bootstrap repository's hashes change when a hardfork changes the artifacts, so re-verify on every such update. Apply hardfork artifacts before the activation timestamp to avoid a chain-divergence stall.

## Notes

- This stack holds no project-side private keys. The sequencer, batcher, proposer, and challenger keys stay on the Whitechain side. You operate a follow-only node.
- The Engine API on `8551` is bound only to the profile's own compose network. Do not publish it.
- op-node RPC (`9545`) is bound to loopback only and does not enable the `admin` namespace. op-reth exposes no `admin` namespace. The node therefore exposes no administrative or state-mutating control surface to the network.
- On `full-snap-node` the EL P2P port `30303` is published on all interfaces (TCP and UDP) – op-reth needs it to snap-sync and to peer over devp2p. It carries no RPC and no administrative methods. `full-node` and `archive-node` do not publish it.
- `keys/<profile>/jwt.txt` is generated locally and used only between the op-node and op-reth of that profile. Each profile has its own secret and its own compose network, so one profile's Engine API credential never grants access to another's. It does not need to match anything outside. If you upgraded from a version that used a single `keys/jwt.txt`, the next `make up` generates the per-profile secret and recreates both containers with it; the old file is unused and can be deleted.
- To resync a profile from scratch: `make down PROFILE=<p>`, then `rm -rf data/<p>/op-reth data/<p>/op-node`, then `make up PROFILE=<p>`. On `full-node`/`archive-node` this means re-executing the chain from genesis, so do not do it on a node that is serving traffic without a maintenance window.
