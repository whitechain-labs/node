# Run a Whitechain RPC Node

A tutorial for running your own Whitechain RPC node that follows the canonical L2 chain.

## Objectives

By the end of this tutorial you will:

* Deploy an external Whitechain RPC node (op-reth + op-node) on your own server
* Choose the right node profile – `full-snap-node`, `full-node`, or `archive-node`
* Optionally restore a published `op-reth` snapshot to skip the long initial sync
* Have it follow the canonical Whitechain L2 chain over P2P and L1 derivation
* Expose JSON-RPC and WebSocket endpoints for your applications
* Forward end-user transactions to the Whitechain network

## How It Works

The Whitechain sequencer is closed and is not directly reachable from the public internet. Your node does not need any access to it. The node:

1. Reads L1 batches from your own Ethereum L1 RPC and Beacon endpoints.
2. Pulls unsafe blocks from the Whitechain network over libp2p.
3. Forwards `eth_sendRawTransaction` calls to the public Whitechain RPC URL (`WHITECHAIN_PUBLIC_RPC`), which routes them to the sequencer.

You only need:

* Your own L1 RPC and Beacon endpoints
* A public IP for the node (`PUBLIC_IP`), advertised for P2P
* Outbound network access to the public Whitechain endpoints
* The published `genesis.json` and `rollup.json` artifacts for the chosen network
* For `full-snap-node`: a trusted reth enode to snap-sync from (`WHITECHAIN_RETH_TRUSTED_PEERS`)

> **Note:** This stack does not contain any project-side private keys. The sequencer, batcher, proposer, and challenger keys remain on the Whitechain side. You operate a follow-only node.

## Concepts: storage vs sync method

A node is defined by two independent choices. The profiles are fixed combinations of them.

**Storage** – how much state op-reth keeps:

* **Pruned** (`--full`) – keeps only recent state, prunes history. Smallest disk.
* **Archive** (no `--full`) – keeps full historical state. Largest disk. Required for historical tracing.

**Sync method** – how op-reth obtains state:

* **consensus-layer** (op-node default) – op-node derives blocks from L1 and feeds them to op-reth, which **re-executes every transaction** from genesis. No EL peer needed, but the initial sync is **long** unless you restore a snapshot.
* **execution-layer** (`--syncmode=execution-layer`, "snap") – op-reth **snap-syncs the state snapshot** from a trusted reth peer over EL P2P. Fast, no snapshot restore, but needs a reachable seed peer. Snap sync only produces pruned state – it cannot build an archive.

| Storage | consensus-layer (re-execute) | execution-layer (snap) |
| --- | --- | --- |
| Pruned (`--full`) | `full-node` | `full-snap-node` |
| Archive | `archive-node` | not supported |

## Choosing a Node Profile

The stack ships three profiles. Pick one with `PROFILE=<profile>` or a per-profile `make` target.

| Profile | Use it for | Storage | Sync method | Snapshot | Public RPC |
| --- | --- | --- | --- | --- | --- |
| `full-snap-node` | Recommended default – fastest, simplest bootstrap | Pruned (`--full`) | execution-layer (snap) | Not needed | Yes |
| `full-node` | Public RPC without snap sync | Pruned (`--full`) | consensus-layer | Recommended | Yes |
| `archive-node` | Explorers, indexers, historical tracing | Full history | consensus-layer | Recommended | Yes |

* **full-snap-node** – the recommended default and fastest, simplest way to bring up a node. Pruned execution state and the basic RPC namespaces `eth,net,web3,rpc`. Bootstraps by snap-syncing from a trusted reth peer (`WHITECHAIN_RETH_TRUSTED_PEERS`) instead of re-executing, so it needs no snapshot. Use it when you have a reachable seed reth enode.
* **full-node** – same pruned state and namespaces as `full-snap-node`, but syncs in consensus-layer mode by re-executing the chain from L1. Use it when you have no trusted reth peer to snap-sync from. Restore a snapshot to avoid a long initial sync.
* **archive-node** – keeps full historical state and adds the `debug`, `trace`, `txpool`, `reth` namespaces plus higher RPC limits. Required for historical `eth_call`, `debug_traceTransaction`, and log-heavy indexing. Archive cannot snap-sync, so it always syncs by re-executing from L1 – restore a snapshot to avoid a very long initial sync. Needs the most disk and RAM.

## Prerequisites

### Hardware

| Component | full-snap-node / full-node | archive-node |
| --- | --- | --- |
| CPU | 4+ cores | 8+ cores |
| RAM | 16 GB | 32 GB |
| Storage | NVMe SSD, 500 GB min / 1 TB recommended (≥ 2× current chain size + 20%) | NVMe SSD, sized for full history (≥ 1 TB) |
| Network | 100 Mbps+ | 1 Gbps |

Disk usage grows with the chain. Restoring a snapshot (below) does not change the steady-state growth – it only saves the initial sync time.

### Network ports

Only one profile runs at a time, so all profiles share the same host ports. Each is remappable through the env var in parentheses.

| Port | Default | Env var |
| --- | --- | --- |
| HTTP RPC | `8545` | `HOST_HTTP_PORT` |
| WebSocket RPC | `8546` | `HOST_WS_PORT` |
| op-node RPC | `9545` (loopback `127.0.0.1` only) | `HOST_OP_NODE_RPC_PORT` |
| op-node P2P (TCP+UDP) | `9222` | `HOST_OP_NODE_P2P_PORT` |
| EL P2P (TCP+UDP) | `30303` (disabled by default) | `HOST_EL_P2P_PORT` |

The Engine API (`8551`) stays on the internal compose network and is not published. op-node RPC (`9545`) is bound to loopback (`127.0.0.1`) only – reachable for local monitoring on the host but never from the network – and the `admin` namespace is not enabled, so it serves only the read-only `optimism` and `opp2p` status namespaces. The EL P2P port (`30303`) is not published by default (snap sync only needs outbound connectivity to the trusted peer); its host mapping is commented out in `docker-compose.yml`, uncomment it only if you want inbound EL peering. Run only one profile at a time – they all bind the same host ports; to run two side by side on one host, override one profile's ports in `.env`.

### Software

* Docker with Compose v2
* `make`, `git`, `openssl`, `curl`, `jq`
* `zstd` and `tar` if you restore from a snapshot

### L1 RPC and Beacon

You need your own Ethereum L1 RPC and Beacon endpoints. Either run your own L1 node or use a third-party provider.

| Whitechain network | L1 chain |
| --- | --- |
| Whitechain mainnet | Ethereum mainnet |
| Whitechain testnet | Ethereum Sepolia |

### Resources from the Whitechain team

Two static files for the chosen network:

* `genesis.json` – L2 execution genesis
* `rollup.json` – OP rollup configuration

Public endpoints and (optionally) a snapshot:

* `WHITECHAIN_PUBLIC_RPC` – public Whitechain JSON-RPC URL, the transaction-forwarding target
* `WHITECHAIN_PUBLIC_OP_NODE_P2P` – optional static op-node peer, `/dns4/<host>/tcp/9222/p2p/<peerID>` or `/ip4/<ip>/tcp/9222/p2p/<peerID>`
* `WHITECHAIN_RETH_TRUSTED_PEERS` – trusted reth enode for `full-snap-node` to snap-sync from
* A published `op-reth` database snapshot URL (recommended for `full-node` / `archive-node`)

## Running a Node

1. Get the manifests directory `public-rpc-node/` on your server.
2. Place the network artifacts under `artifacts/<network>/`:

   ```
   public-rpc-node/artifacts/mainnet/genesis.json
   public-rpc-node/artifacts/mainnet/rollup.json
   ```

   For the testnet use `artifacts/testnet/`. The folder name must match `WHITECHAIN_NETWORK` in `.env`.

3. Create your `.env`:

   ```bash
   cp .env.mainnet.example .env   # or .env.testnet.example
   ```

   Fill in the required values:

   ```
   WHITECHAIN_NETWORK=mainnet
   PUBLIC_IP=203.0.113.10
   WHITECHAIN_PUBLIC_RPC=https://rpc.whitechain.io

   L1_RPC_URL=https://your-l1-rpc.example.com
   L1_BEACON_URL=https://your-l1-beacon.example.com
   L1_RPC_KIND=basic
   ```

   For the `full-snap-node` profile also set:

   ```
   WHITECHAIN_RETH_TRUSTED_PEERS=enode://<pubkey>@<ip>:30303
   ```

   `L1_RPC_KIND` is `basic` by default. Set it to one of `alchemy`, `quicknode`, `infura`, `parity`, `nethermind`, `debug_geth`, `erigon`, `standard`, `any` if your provider supports extra receipt-fetching methods.

4. Restore an `op-reth` snapshot if you run `full-node` or `archive-node` (recommended) – see [Restoring from a snapshot](#restoring-from-a-snapshot). `full-snap-node` skips this; it snap-syncs from `WHITECHAIN_RETH_TRUSTED_PEERS`.

5. Start the profile you chose:

   ```bash
   make up-full-snap-node   # recommended default: pruned node, snap-syncs from a trusted peer
   # make up-full-node      # pruned node, consensus-layer sync (re-executes from L1)
   # make up-archive-node   # archive node
   ```

   `make up` will:

   1. Validate that `.env` and `artifacts/<network>/{genesis,rollup}.json` exist.
   2. Generate `keys/jwt.txt` if missing.
   3. Run `docker compose --profile <profile> up -d`.

6. Confirm you get a response from your node (use the profile's HTTP port):

   ```bash
   curl -d '{"id":0,"jsonrpc":"2.0","method":"eth_getBlockByNumber","params":["latest", false]}' \
     -H 'Content-Type: application/json' http://127.0.0.1:8545
   ```

> **Warning:** For `full-node` and `archive-node`, initial sync from genesis re-executes every transaction and can take from minutes on a fresh testnet to many hours on a long-running chain. Restore a snapshot to cut this down. `full-snap-node` bootstraps fast from its trusted peer instead.

## Restoring from a Snapshot

This applies to the **non-snap** profiles, `full-node` and `archive-node`. They sync in consensus-layer mode and re-execute the chain from genesis, which is slow. The Whitechain team publishes periodic `op-reth` database snapshots. Restoring one lets you start near a recent block and only derive the gap since the snapshot was taken.

> `full-snap-node` does **not** need this – it snap-syncs the state directly from `WHITECHAIN_RETH_TRUSTED_PEERS`.

1. Stop the node if running:

   ```bash
   make down PROFILE=full-node
   ```

2. Download and extract the snapshot for your network and profile into the matching data directory. The archive expands into the `op-reth` `db`, `static_files`, and related folders:

   ```bash
   mkdir -p data/full-node/op-reth
   curl -L "<WHITECHAIN_SNAPSHOT_URL>/op-reth-mainnet-full.tar.zst" \
     | zstd -d \
     | tar -x -C data/full-node/op-reth
   ```

   After extraction you should have `data/full-node/op-reth/db`, `data/full-node/op-reth/static_files`, and so on.

3. Start the node and watch it catch up:

   ```bash
   make up-full-node
   make logs-full-node
   ```

Rules of thumb:

* Match the snapshot to the **profile**. A pruned snapshot cannot serve archive queries – restore an archive snapshot into `data/archive-node/op-reth` for an archive node.
* Restore only the `op-reth` data. The `op-node` directory (`peerstore`, `discovery`, `safedb`) is rebuilt automatically.
* You still need a working L1 RPC + Beacon to derive everything after the snapshot block.
* Without a snapshot, the node re-executes from genesis – expect a long initial sync.

## Creating a Backup

This is the procedure the Whitechain team uses to produce the published `op-reth` snapshots, and the same steps you can follow to take your own daily backup of a `full-node` / `archive-node` datadir. Back up only the `op-reth` data; the `op-node` directory rebuilds itself.

1. Stop the node to get a consistent on-disk database:

   ```bash
   make down PROFILE=full-node
   ```

2. Archive and compress the `op-reth` datadir (`db`, `static_files`, and related folders):

   ```bash
   tar -c -C data/full-node/op-reth . | zstd -o op-reth-mainnet-full.tar.zst
   ```

3. Restart the node so it resumes following the chain:

   ```bash
   make up PROFILE=full-node
   ```

4. Copy the archive to the location clients download from (object storage, mirror, etc.). Clients then restore it as in [Restoring from a Snapshot](#restoring-from-a-snapshot).

> **Note:** Match the archive name to the network and profile it was taken from. A pruned (`full-node`) backup cannot serve archive queries.

## Data Layout

Each profile keeps its own data subtree so profiles never clash:

```
data/
  full-snap-node/{op-reth,op-node}
  full-node/{op-reth,op-node}
  archive-node/{op-reth,op-node}
```

Snapshots are restored into `data/<profile>/op-reth/`.

### Syncing

> **Warning:** In the first few minutes after start the node may report no peers ready to handle block requests until the static peer handshake completes. This is expected – wait for the handshake with `WHITECHAIN_PUBLIC_OP_NODE_P2P` to finish and a connected peer to appear before treating it as an error.

Watch the logs:

```bash
make logs-full-snap-node # or logs-full-node / logs-archive-node
```

In `op-node` you should see, in order:

* `Connected to L1 Beacon API`
* `started p2p host` with your local peerID
* `Advancing bq origin` lines, indicating L1 batch derivation
* `Inserted new L2 unsafe block` lines, indicating blocks are being applied to op-reth

op-node RPC is bound to loopback `127.0.0.1:9545` (reachable from the host only). Example sync-lag check:

```bash
echo "Latest synced block behind by: $((($(date +%s) - $( \
  curl -s -X POST http://127.0.0.1:9545 \
    -H 'Content-Type: application/json' \
    --data '{"jsonrpc":"2.0","method":"optimism_syncStatus","params":[],"id":1}' \
  | jq -r .result.unsafe_l2.timestamp)) / 60)) minutes"
```

Check connected peers:

```bash
curl -s -X POST http://127.0.0.1:9545 \
  -H 'Content-Type: application/json' \
  --data '{"jsonrpc":"2.0","method":"opp2p_peers","params":[true],"id":1}' \
  | jq '.result.totalConnected'
```

## Operating the Node

Generic targets take `PROFILE=full-snap-node|full-node|archive-node` (default `full-snap-node`):

```bash
make up PROFILE=archive-node     # start
make down PROFILE=archive-node   # stop
make reup PROFILE=archive-node   # down + up
make ps PROFILE=archive-node     # status
make logs PROFILE=archive-node   # tail logs
make config PROFILE=archive-node # render merged compose config
```

Per-profile shortcuts exist for each: `make up-full-snap-node`, `make logs-full-node`, `make reup-archive-node`, etc. `make ensure-jwt` generates `keys/jwt.txt` manually; `make help` lists everything.

To wipe local state and resync a profile from genesis:

```bash
make down PROFILE=full-node
rm -rf data/full-node/op-reth data/full-node/op-node
make up PROFILE=full-node
```

> **Warning:** This deletes the local chain database for that profile. The next start re-derives the chain from L1 and pulls unsafe blocks over P2P. For `full-node`/`archive-node` prefer restoring a snapshot over a full genesis resync, and do not run this against a production-serving node without a maintenance window.

## Sending Transactions

Applications submit transactions to your local `op-reth` HTTP port. The node forwards them to `WHITECHAIN_PUBLIC_RPC`, which routes them to the sequencer.

```bash
curl -X POST http://127.0.0.1:8545 \
  -H 'Content-Type: application/json' \
  --data '{"jsonrpc":"2.0","method":"eth_sendRawTransaction","params":["0x..."],"id":1}'
```

You do not need any direct access to the sequencer. The pattern is the same as on Base (where nodes forward to `https://mainnet-sequencer.base.org`).

> **Note:** If you restart your node, in-flight transactions remain in the public RPC mempool, not in your local node.

## Available RPC Methods

`op-reth` namespaces depend on the profile:

* `full-snap-node` / `full-node` – HTTP/WS on its ports: `eth`, `net`, `web3`, `rpc`
* `archive-node` – HTTP: `eth`, `net`, `web3`, `rpc`, `debug`, `trace`, `txpool`, `reth`; WS: `eth`, `net`, `web3`, `rpc`

`op-node` exposes on RPC `9545` (loopback `127.0.0.1` only):

* `optimism` – rollup state, including `optimism_syncStatus` and `optimism_outputAtBlock`
* `opp2p` – P2P peer information, including `opp2p_self` and `opp2p_peers`

The `admin` namespace is not enabled (no `--rpc.enable-admin`), so op-node exposes no administrative methods.

## Updating the Node

Image versions are pinned in `docker-compose.yml`. To upgrade:

```bash
git pull
docker compose pull
make reup PROFILE=full-snap-node
```

If the upgrade includes a new hardfork, replace `artifacts/<network>/rollup.json` with the published version before running `make reup`.

> **Note:** The Whitechain team announces hardforks in advance. Apply the new `rollup.json` and `genesis.json` (if changed) before the activation timestamp to avoid a chain-divergence stall.

## Security Notes

* The Engine API on port `8551` is bound only to the internal compose network and is not exposed to the host. Do not publish it.
* op-node RPC on port `9545` is bound to loopback (`127.0.0.1`) only, so it is reachable from the host but not from the network. The `admin` namespace is not enabled, so it serves only read-only rollup and P2P status methods.
* op-reth exposes no `admin` namespace on any profile. The public JSON-RPC (`8545`) and WebSocket (`8546`) ports serve only read-only namespaces (`eth`, `net`, `web3`, `rpc`; archive adds `debug`, `trace`, `txpool`, `reth`). The node exposes no state-mutating or administrative control surface.
* `keys/jwt.txt` is local to your machine and is used only between `op-node` and `op-reth` in this stack. It does not need to match anything outside.
* The node holds no project-side private keys. Operate it as a read and forward node.
* Restrict inbound access to the JSON-RPC ports you choose to expose – put them behind a firewall, reverse proxy, or rate limiter before serving untrusted clients.

## Troubleshooting

### `Missing .env`

Copy from `.env.mainnet.example` (or `.env.testnet.example`) and fill the values listed in [Running a Node](#running-a-node).

### `Missing artifacts/<network>/genesis.json`

Place `genesis.json` and `rollup.json` for the chosen network under `artifacts/<network>/`. The folder name has to match `WHITECHAIN_NETWORK` in `.env`.

### `set PUBLIC_IP in .env`

Compose refuses to start without `PUBLIC_IP`. Set it to the public IP that the node should advertise for P2P.

### `set WHITECHAIN_PUBLIC_RPC in .env`

You did not set the transaction-forwarding target. Set it to the public Whitechain RPC URL.

### `set WHITECHAIN_RETH_TRUSTED_PEERS in .env` (full-snap-node only)

The `full-snap-node` profile needs a trusted reth enode to snap-sync from. Set it to `enode://<pubkey>@<ip>:30303`.

### `failed to insert unsafe payload ... node is syncing` (full-node / archive-node, early sync)

Expected during the initial consensus-layer sync of a fresh database. op-node receives an unsafe head from gossip but op-reth has not re-executed up to its parent yet, so the forkchoice update returns `SYNCING`. Meanwhile `Advancing bq origin` shows L1 derivation is progressing. The messages stop once the node catches up. To avoid the long catch-up, restore a snapshot (`full-node`/`archive-node`) or use `full-snap-node`.

### Restored snapshot but the node resyncs from genesis

* Confirm the data landed in the right place: `data/<profile>/op-reth/db` and `data/<profile>/op-reth/static_files` must exist.
* Confirm the snapshot matches `WHITECHAIN_NETWORK` and the profile you start.
* Make sure the node was stopped during extraction.

### Sync is slow

Common causes, in order of likelihood:

1. No snapshot restored on a long-running chain (`full-node`/`archive-node`), so the node re-executes from genesis. Restore one, or use `full-snap-node`.
2. L1 endpoint is rate-limited or slow. Switch to a faster L1 RPC and Beacon, or use your own node.
3. Disk I/O is the bottleneck. Move `data/` to NVMe storage.

### `full-snap-node` is not snap-syncing

* Confirm `WHITECHAIN_RETH_TRUSTED_PEERS` is a reachable reth enode (`enode://<pubkey>@<ip>:30303`) and the peer is up.
* Confirm outbound EL P2P (devp2p) to that peer is not blocked by a firewall.
* Check op-node logs show `--syncmode=execution-layer` is active and op-reth reports `Syncing` against the trusted peer.

### `optimism_syncStatus` shows `unsafe_l2.number = 0`

The node has not yet inserted the first L2 block. Give it a minute. If it stays at 0:

* Check op-node logs for `Reset of Engine is completed` and `Inserted new L2 unsafe block`. If absent, the engine is not connected. Ensure `op-reth` is healthy on its HTTP port.
* Confirm the genesis block hash in op-node logs matches the one in `rollup.json`.

### `Error: nonce has already been used` when deploying via the node

The node is not fully synced. Wait for `optimism_syncStatus` lag to drop close to zero before submitting transactions.

## What This Node Does Not Provide

This setup is a follow-only RPC node. It does not include:

* Block builder or sequencer roles
* Batcher, proposer, or challenger
* Flashblocks pre-confirmation stream

If your application needs sub-second pre-confirmations, contact the Whitechain team for the Flashblocks WebSocket URL and a separate guide. The current `public-rpc-node` stack does not subscribe to the Flashblocks stream.
