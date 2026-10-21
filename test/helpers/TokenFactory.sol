// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SoothToken} from "../../src/SoothToken.sol";

/// @dev Test-only factory demonstrating constructor custody and exact launch transfers.
contract TokenFactory {
    function deploy(bytes32 salt) external returns (SoothToken) {
        return new SoothToken{salt: salt}();
    }

    function distribute(SoothToken token, address recipient, uint256 amount) external returns (bool) {
        return token.transfer(recipient, amount);
    }
}
