# Artifacts for Whitechain Testnet

`genesis.json` and `rollup.json` for Whitechain Testnet belong here. They are **not** shipped in this repository – copy them in from the authoritative source:

- Repository: [whitechain-labs/whitechain-bootstrap](https://github.com/whitechain-labs/whitechain-bootstrap), directory `testnet/`
- Docs: [Network artifacts](https://docs.whitechain.io/operate/run-a-node/network-artifacts)

```bash
git clone https://github.com/whitechain-labs/whitechain-bootstrap.git
cd whitechain-bootstrap

# compare against the SHA-256 hashes published in that repository's README
shasum -a 256 testnet/genesis.json testnet/rollup.json

cp testnet/genesis.json testnet/rollup.json <public-rpc-node>/artifacts/testnet/
```

The bootstrap repository is the single source of truth for both the files and their hashes; this directory intentionally holds no copy of the artifacts and no checksum file of its own. Verify the hashes before starting a node – `genesis.json` decides which chain the node treats as canonical. `make up` additionally cross-checks the two files against each other (L2 chain ID, genesis timestamp, L1 chain ID); that catches a mismatched pair, but only the hash comparison above establishes authenticity. The published hashes change when a hardfork changes the artifacts, so re-verify on every update.
