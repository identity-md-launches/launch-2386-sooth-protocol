# Vendored dependencies

All dependencies are ordinary files in this repository, with no submodules or runtime downloads. Only Solidity sources required for the project and upstream license files are included.

| Dependency | Release | Exact upstream commit | Local path | License |
| --- | --- | --- | --- | --- |
| [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts/tree/acd4ff74de833399287ed6b31b4debf6b2b35527) | `v5.2.0` | `acd4ff74de833399287ed6b31b4debf6b2b35527` | `lib/openzeppelin-contracts/` | MIT |
| [Forge Standard Library](https://github.com/foundry-rs/forge-std/tree/3b20d60d14b343ee4f908cb8079495c07f5e8981) | `v1.9.6` | `3b20d60d14b343ee4f908cb8079495c07f5e8981` | `lib/forge-std/` | MIT or Apache-2.0 |

OpenZeppelin includes `ERC20.sol`, `IERC20.sol`, `IERC20Metadata.sol`, `Context.sol`, and `draft-IERC6093.sol`. Forge Standard Library includes its `src/` directory for test utilities only. The copied files are unmodified upstream sources. Remappings are explicit in `foundry.toml`.

`DEPENDENCIES.sha256` records SHA-256 hashes of all vendored files, including licenses. Verify from the repository root:

```sh
sha256sum -c DEPENDENCIES.sha256
```

The pinned compiler is provisioned by Foundry/the verification environment; no compiler binary is vendored.
