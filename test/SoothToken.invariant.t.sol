// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {SoothToken} from "../src/SoothToken.sol";

/// @dev Tracks an independent ledger over a closed set of actors. Both successful and rejected
/// transfers are generated; no deal/storage cheatcodes change token balances or allowances.
contract TokenHandler is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    SoothToken public immutable token;
    address[4] public actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(SoothToken token_) {
        token = token_;
        actors[0] = makeAddr("actor0");
        actors[1] = makeAddr("actor1");
        actors[2] = makeAddr("actor2");
        actors[3] = makeAddr("actor3");
        expectedBalance[actors[0]] = SUPPLY;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = expectedBalance[from];
        uint256 amount = _transferAmount(amountSeed, balance);

        vm.prank(from);
        (bool success, bytes memory result) = address(token).call(abi.encodeCall(token.transfer, (to, amount)));
        if (amount > balance) {
            assertFalse(success);
            assertEq(
                result, abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount)
            );
        } else {
            assertTrue(success);
            assertTrue(abi.decode(result, (bool)));
            expectedBalance[from] -= amount;
            expectedBalance[to] += amount;
        }
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        // Deliberately revisit revocation, unlimited approval, and the largest finite approval.
        uint256 mode = amountSeed % 8;
        uint256 amount = mode == 0
            ? 0
            : mode == 1 ? type(uint256).max : mode == 2 ? type(uint256).max - 1 : mode == 3 ? 1 : amountSeed;
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amountSeed) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 allowance = expectedAllowance[owner][spender];
        uint256 balance = expectedBalance[owner];
        uint256 available = balance < allowance ? balance : allowance;
        uint256 amount = _transferAmount(amountSeed, available);

        vm.prank(spender);
        (bool success, bytes memory result) =
            address(token).call(abi.encodeCall(token.transferFrom, (owner, to, amount)));
        if (amount > allowance) {
            assertFalse(success);
            assertEq(
                result,
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowance, amount)
            );
        } else if (amount > balance) {
            assertFalse(success);
            assertEq(
                result, abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, amount)
            );
        } else {
            assertTrue(success);
            assertTrue(abi.decode(result, (bool)));
            if (allowance != type(uint256).max) expectedAllowance[owner][spender] -= amount;
            expectedBalance[owner] -= amount;
            expectedBalance[to] += amount;
        }
    }

    function rejectInvalidAddress(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed, uint8 operation)
        external
    {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 balance = expectedBalance[owner];
        bytes memory data;
        bytes memory expectedError;
        address caller = owner;

        if (operation % 3 == 0) {
            data = abi.encodeCall(token.approve, (address(0), amountSeed));
            expectedError = abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0));
        } else if (operation % 3 == 1) {
            data = abi.encodeCall(token.transfer, (address(0), bound(amountSeed, 0, balance)));
            expectedError = abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0));
        } else {
            uint256 allowance = expectedAllowance[owner][spender];
            uint256 available = balance < allowance ? balance : allowance;
            // Reach recipient validation even when the current allowance is zero. A reverted
            // delegated transfer must not consume any finite allowance in the independent ledger.
            data = abi.encodeCall(token.transferFrom, (owner, address(0), bound(amountSeed, 0, available)));
            expectedError = abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0));
            caller = spender;
        }

        vm.prank(caller);
        (bool success, bytes memory result) = address(token).call(data);
        assertFalse(success);
        assertEq(result, expectedError);
        // No ghost changes: both invariants also check all unrelated balances and allowances.
    }

    function _transferAmount(uint256 seed, uint256 available) private pure returns (uint256) {
        // Half the modes are valid for the current state; the others probe exact boundaries
        // and unrestricted amounts. This avoids a campaign dominated by trivial overspends.
        uint256 mode = seed % 8;
        if (mode == 0) return 0;
        if (mode == 1) return 1;
        if (mode == 2) return available;
        if (mode == 3) return available + 1; // available is at most the fixed supply.
        if (mode == 4) return type(uint256).max;
        if (mode == 5) return seed;
        return bound(seed, 0, available);
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract SoothTokenInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    SoothToken private token;
    TokenHandler private handler;

    function setUp() public {
        token = new SoothToken();
        handler = new TokenHandler(token);
        token.transfer(handler.actors(0), SUPPLY);

        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = TokenHandler.transfer.selector;
        selectors[1] = TokenHandler.approve.selector;
        selectors[2] = TokenHandler.transferFrom.selector;
        selectors[3] = TokenHandler.rejectInvalidAddress.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_SupplyIsFixedAndBalancesAreConserved() public view {
        uint256 sum;
        for (uint256 i; i < 4; ++i) {
            address actor = handler.actors(i);
            uint256 balance = token.balanceOf(actor);
            assertEq(balance, handler.expectedBalance(actor));
            sum += balance;
        }
        assertEq(sum, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
        assertEq(token.balanceOf(address(token)), 0);
    }

    function invariant_AllowancesMatchExplicitApprovalsAndSuccessfulSpending() public view {
        for (uint256 i; i < 4; ++i) {
            address owner = handler.actors(i);
            assertEq(token.allowance(owner, address(0)), 0);
            assertEq(token.allowance(address(0), owner), 0);
            for (uint256 j; j < 4; ++j) {
                address spender = handler.actors(j);
                assertEq(token.allowance(owner, spender), handler.expectedAllowance(owner, spender));
            }
        }
    }

    function test_HandlerExercisesSpendingRevocationAndRecovery() public {
        // Pin a nonzero sequence so a passing campaign cannot conceal a harness that only
        // generates approvals, zero transfers, or failures. Seeds select the documented modes.
        address owner = handler.actors(0);
        address spender = handler.actors(1);
        address recipient = handler.actors(2);
        handler.approve(0, 1, 20);
        handler.rejectInvalidAddress(0, 1, 20, 0);
        handler.rejectInvalidAddress(0, 1, 20, 1);
        handler.rejectInvalidAddress(0, 1, 20, 2);
        assertEq(token.allowance(owner, spender), 20);
        invariant_SupplyIsFixedAndBalancesAreConserved();
        invariant_AllowancesMatchExplicitApprovalsAndSuccessfulSpending();

        handler.transferFrom(0, 1, 2, 2); // Spend the whole allowance.
        assertEq(token.balanceOf(recipient), 20);
        assertEq(token.allowance(owner, spender), 0);
        handler.approve(0, 1, 1); // Unlimited approval, then explicit revocation.
        handler.approve(0, 1, 0);
        handler.transferFrom(0, 1, 2, 1); // Rejected: revoked allowance.
        assertEq(token.balanceOf(recipient), 20);
        handler.transfer(2, 0, 2); // Return the entire balance.
        assertEq(token.balanceOf(owner), SUPPLY);

        handler.approve(0, 1, 1);
        handler.transferFrom(0, 1, 2, 2); // Spend the whole supply with unlimited approval.
        assertEq(token.balanceOf(recipient), SUPPLY);
        assertEq(token.allowance(owner, spender), type(uint256).max);
        handler.transfer(2, 0, 2);
        invariant_SupplyIsFixedAndBalancesAreConserved();
        invariant_AllowancesMatchExplicitApprovalsAndSuccessfulSpending();
    }
}
