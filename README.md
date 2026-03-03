# Anonymous Airdrop

Claim airdrop tokens without revealing which eligible address you are. A ZK proof proves Merkle tree membership, and tokens land at a fresh stealth address — nothing links the claim back to the original address.

**Noir** · **Solidity** · **Foundry** · **UltraHonk** · **ERC-5564/6538**

## How It Works

1. Each eligible address gets a secret during tree construction — knowing it lets you prove membership
2. User generates a one-time stealth address (ECDH) with no on-chain link to their identity
3. ZK proof bundles the secret + stealth address: proves eligibility and locks tokens to the stealth address
4. A relayer submits the proof on-chain — the user never touches the chain

## Highlights

**Circuit (Noir)** — Poseidon2 Merkle proof + nullifier, recipient bound as public input, stealth address receiver remains private and bound to secret

**On-chain (Solidity)** — UltraHonk verifier, nullifier tracking, ERC-5564 announcements with viewTag filtering

**Testing (Foundry)** — E2E via FFI (TS generates proof + stealth address), fork tests on Sepolia against real ERC-5564 Announcer, replay/tamper coverage

## Standards

- [ERC-5564](https://eips.ethereum.org/EIPS/eip-5564) — Stealth Address Announcements (emit events so scanners can find payments)
- [ERC-6538](https://eips.ethereum.org/EIPS/eip-6538) — Stealth Meta-Address Registry (publish meta-address for stealth address generation)

## Build

```bash
cd circuits && nargo compile
cd contracts && forge build && forge test
```

> **Note:** Tests require `ffi = true` in `foundry.toml`. Fork tests need `RPC_URL` (Ethereum Mainnet).

See [`diagram.excalidraw`](./diagram.excalidraw) for the full flow.
