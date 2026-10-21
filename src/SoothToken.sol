// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Sooth Protocol (SOOTH)
/// @notice A fixed-supply, 18-decimal ERC-20 minted entirely to its deployer.
/// @dev The constructor is the only mint path. There are no administrative roles.
contract SoothToken is ERC20 {
    /// @notice One billion SOOTH, expressed in the token's smallest units.
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    /// @dev When a factory deploys the token, the factory receives the entire supply.
    constructor() ERC20("Sooth Protocol", "SOOTH") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
