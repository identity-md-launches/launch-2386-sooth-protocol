# Sooth Protocol (SOOTH)

`src/SoothToken.sol:SoothToken` is an ERC-20 with a fixed supply of **1,000,000,000 SOOTH** and **18 decimals**. Its constructor mints the entire supply exactly once to `msg.sender`. The implementation uses the vendored OpenZeppelin Contracts ERC-20 without changing its transfer or allowance logic.

## Deployment parameters

| Parameter | Value |
| --- | --- |
| Solidity contract identifier | `SoothToken` |
| Name | `Sooth Protocol` |
| Symbol | `SOOTH` |
| Decimals | `18` |
| Total supply in smallest units | `1000000000000000000000000000` (`10^27`) |
| Named supply constant | `INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18` |
| Constructor arguments | None (`[]`) |
| Constructor ETH value | `0` |
| Initial recipient | Immediate deploying address (`msg.sender`) |
| Intended launch chain | Robinhood Chain, chain ID `4663`, as specified in the assignment |
| Compiler | Solidity `0.8.26` |
| Compiler settings | Optimizer enabled, 200 runs; EVM target `cancun`; `bytecode_hash = "none"` |
| Build artifact | `out/SoothToken.sol/SoothToken.json` |

The constructor requires no external contracts, addresses, initialization, or library linking. The Cancun EVM target matches Solidity 0.8.26's default and permits the transient-storage operations used by the supplied launch pool harness. The token itself has no chain-specific logic, clocks, oracles, sequencer assumptions, or bridge dependencies.

When the launch factory deploys the token, **the factory receives all tokens**, not the transaction origin or the wallet calling the factory. A direct deployment instead gives all tokens to that direct deployer. The deployer must be able to hold and transfer ERC-20 tokens. Use the creation bytecode from the artifact with no appended arguments and no ETH value.

The launch service prepares the manifest and executes deployment separately. This project contains the token only; no application contracts or launch manifest are needed here. Nothing in the constructor distributes or reserves tokens. The assignment's 10% swarm, 70% pool, and 20% remainder allocations are handled by the launch factory after deployment. Pool configuration and pricing are external to the token.

## Behavior and assumptions

- Transfers deliver exactly the requested amount. There are no transfer fees, burns, rebases, exemptions, holding limits, or trading gates.
- There is no owner, minter, pauser, blacklist, seizure mechanism, upgrade path, or public burn function. The deployer has the same permissions as every other holder after deployment. Supply remains constant.
- `transfer`, `approve`, and `transferFrom` return `true` on success and revert with OpenZeppelin ERC-20 custom errors on failure. Failed calls preserve balances and allowances.
- Zero-value transfers between nonzero addresses succeed and emit `Transfer`. Self-transfers preserve balance. Transfers to the zero address and approvals to a zero spender revert.
- `approve` replaces the caller's allowance for a spender. `transferFrom` consumes finite allowances; `type(uint256).max` means an unlimited allowance and is not reduced. Even a holder using `transferFrom` on their own balance needs an allowance for nonzero spending.
- Deployment emits one `Transfer` from the zero address. Transfers emit `Transfer`, and explicit approvals emit `Approval`. OpenZeppelin v5 does not emit `Approval` when `transferFrom` reduces an allowance; integrations should query `allowance` for its current value.
- This is a plain ERC-20 without permit or recipient callbacks. It has no payable entry point or asset recovery function. Sending tokens to the token contract itself, or to another contract unable to transfer them, can permanently lock those tokens without changing total supply.

## Build and check

Install Foundry and provide Solidity `0.8.26` in its compiler cache. All Solidity library sources are included as ordinary files under `lib/`; no package installation, submodules, RPC, secrets, or network access is required once the compiler is available.

```sh
forge build
FOUNDRY_FUZZ_SEED=0x0c18a3ace4e4c897812b5f245beb869f2909966395e21e4eb6afad2030f365c2 forge test
forge fmt --check
```

Tests do not read or change environment variables, use forks, or depend on test order. The shell seed above supplies the assignment's reproducible fuzz input. Configuration uses 512 runs per fuzz test and 128 runs of depth 64 per invariant.

`test/SoothToken.t.sol` covers metadata, a single constructor mint, factory deployment, exact distribution and transfer paths, allowance replacement/revocation, finite and unlimited approvals, zero/self transfers, events, invalid addresses, insufficient funds/allowances, rollback on failure, and rejected mint/admin/upgrade calls. Fuzz tests cover transfer conservation, delegated transfers, approval replacement, and overspending failures. `test/SoothToken.invariant.t.sol` checks supply, balances, and allowances against a separate ledger across sequences of successful and rejected calls.

The factory test verifies token movements for distribution and both pool directions; it does not instantiate a Uniswap pool or claim to run the protected launch harness. The supplied protected tests rely on launch infrastructure, manifest data, and contracts supplied by the independent verifier.

## After launch

There are no owner settings, initialization calls, maintenance transactions, or configuration dependencies. The launch operator is responsible for deploying the specified artifact, verifying its source and constructor parameters, checking the name/symbol/decimals/supply and constructor mint recipient, then completing the factory's distribution and liquidity operations. The constructor's mint event records original custody even if the factory distributes the supply in the same transaction.

Holders control transfers and spender approvals. Integrations should use integer amounts in 18-decimal units and query current allowances. Users should grant only the allowance needed; to replace an existing nonzero allowance, revoke it first and wait for confirmation before approving a new amount, accounting for possible pending spending. Nobody can reverse mistaken transfers, recover assets held by this token contract, or change its code.

Foundry unit, fuzz, and invariant checks are the local validation for this project. Slither and Mythril are not included in that validation. Independent review and the launch verifier's pool/ownership checks remain the launch process's responsibility; local tests are not a security audit.

See `DEPENDENCIES.md` for pinned library revisions, licenses, and source integrity hashes.
