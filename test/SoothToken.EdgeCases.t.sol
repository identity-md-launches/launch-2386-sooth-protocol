// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {SoothToken} from "src/SoothToken.sol";
import {TokenFactory} from "./helpers/TokenFactory.sol";

/// @dev Complements the original suite with boundary values, aliased roles, and failure/retry
/// sequences. Balances and allowances are established only through the token's public API.
/// forge-config: default.fuzz.runs = 1000
contract SoothTokenEdgeCasesTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    SoothToken private token;
    address private alice = makeAddr("edge-alice");
    address private bob = makeAddr("edge-bob");
    address private spender = makeAddr("edge-spender");

    function setUp() public {
        token = new SoothToken();
    }

    function test_OneWeiCanRoundTripThroughDirectAndDelegatedTransfers() public {
        assertTrue(token.transfer(alice, 1));
        vm.prank(alice);
        assertTrue(token.approve(spender, 1));
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(alice, bob, 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 1));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 1);
        vm.prank(bob);
        assertTrue(token.transfer(address(this), 1));
        _assertBalances(0, 0);
    }

    function test_SelfTransferStillRequiresSufficientBalance() public {
        token.transfer(alice, 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 1, 2));
        vm.prank(alice);
        token.transfer(alice, 2);

        vm.prank(alice);
        token.approve(spender, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 1, 2));
        vm.prank(spender);
        token.transferFrom(alice, alice, 2);
        assertEq(token.allowance(alice, spender), type(uint256).max);
        _assertBalances(1, 0);
    }

    function test_HolderUsingTransferFromNeedsTheirOwnAllowance() public {
        token.transfer(alice, 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transferFrom(alice, bob, 1);
        _assertBalances(1, 0);

        vm.prank(alice);
        assertTrue(token.approve(alice, 1));
        vm.prank(alice);
        assertTrue(token.transferFrom(alice, bob, 1));
        assertEq(token.allowance(alice, alice), 0);
        _assertBalances(0, 1);
    }

    function test_OwnerSpenderAndRecipientMayAllBeTheSameAccount() public {
        token.transfer(alice, 1);
        vm.prank(alice);
        token.approve(alice, 1);
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(alice, alice, 1);
        vm.prank(alice);
        assertTrue(token.transferFrom(alice, alice, 1));
        assertEq(token.allowance(alice, alice), 0);
        _assertBalances(1, 0);
    }

    function test_LargestFiniteAllowanceIsConsumedAcrossRepeatedSpending() public {
        uint256 approved = type(uint256).max - 1;
        token.approve(spender, approved);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), approved - 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, SUPPLY - 1));
        assertEq(token.allowance(address(this), spender), approved - SUPPLY);
        _assertBalances(1, SUPPLY - 1);
    }

    function test_UnlimitedApprovalCanBeReplacedByOneWeiThenExhausted() public {
        token.approve(spender, type(uint256).max);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max);

        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Approval(address(this), spender, 1);
        assertTrue(token.approve(spender, 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, 1));
        assertEq(token.allowance(address(this), spender), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), bob, 1);
        _assertBalances(1, 1);
    }

    function test_RevokingUnlimitedApprovalBlocksFurtherNonzeroSpending() public {
        token.approve(spender, type(uint256).max);
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Approval(address(this), spender, 0);
        assertTrue(token.approve(spender, 0));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), bob, 1);
        assertEq(token.allowance(address(this), spender), 0);
        _assertBalances(1, 0);
    }

    function test_ZeroDelegatedTransferEmitsEventWithoutConsumingFiniteAllowance() public {
        vm.prank(alice);
        token.approve(spender, 1);
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(alice, bob, 0);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 0));
        assertEq(token.allowance(alice, spender), 1);
        _assertBalances(0, 0);
    }

    function test_ZeroDelegatedTransferToZeroStillReverts() public {
        token.approve(spender, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), 0);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        _assertBalances(0, 0);
    }

    function test_UnlimitedAllowanceDoesNotPermitMaxUintTransfer() public {
        token.approve(spender, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, type(uint256).max);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        _assertBalances(0, 0);
    }

    function test_ApprovedTransactionOriginDoesNotAuthorizeAnotherCaller() public {
        token.transfer(alice, 1);
        vm.prank(alice);
        token.approve(spender, 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 1));
        vm.prank(bob, spender);
        token.transferFrom(alice, bob, 1);
        assertEq(token.allowance(alice, spender), 1);
        assertEq(token.allowance(alice, bob), 0);
        _assertBalances(1, 0);
    }

    function test_SeparateDeploymentsHaveIndependentSupplyBalancesAndAllowances() public {
        TokenFactory factory = new TokenFactory();
        vm.prank(alice, bob);
        SoothToken first = factory.deploy(keccak256("first-edge-deployment"));
        SoothToken second = factory.deploy(keccak256("second-edge-deployment"));
        assertTrue(address(first) != address(second));
        assertEq(first.balanceOf(alice), 0);
        assertEq(first.balanceOf(bob), 0);
        assertEq(first.balanceOf(address(factory)), SUPPLY);
        assertEq(second.balanceOf(address(factory)), SUPPLY);

        factory.distribute(first, alice, SUPPLY);
        vm.prank(alice);
        first.approve(spender, type(uint256).max);
        assertEq(first.balanceOf(address(factory)), 0);
        assertEq(first.balanceOf(alice), SUPPLY);
        assertEq(second.balanceOf(alice), 0);
        assertEq(second.balanceOf(address(factory)), SUPPLY);
        assertEq(second.allowance(alice, spender), 0);
        assertEq(first.totalSupply(), SUPPLY);
        assertEq(second.totalSupply(), SUPPLY);
        _assertBalances(0, 0);
    }

    function testFuzz_FailedSpendCanBeRetriedAfterFundingWithoutReapproval(
        uint256 balance,
        uint256 amount,
        bool unlimited
    ) public {
        balance = bound(balance, 0, SUPPLY - 1);
        amount = bound(amount, balance + 1, SUPPLY);
        token.transfer(alice, balance);
        uint256 approved = unlimited ? type(uint256).max : amount;
        vm.prank(alice);
        token.approve(spender, approved);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, balance, amount));
        vm.prank(spender);
        token.transferFrom(alice, bob, amount);
        assertEq(token.allowance(alice, spender), approved);
        _assertBalances(balance, 0);

        token.transfer(alice, amount - balance);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, amount));
        assertEq(token.allowance(alice, spender), unlimited ? type(uint256).max : 0);
        _assertBalances(0, amount);
    }

    function testFuzz_InvalidRecipientDoesNotConsumeApprovalAndValidRetrySucceeds(uint256 amount, uint256 approved)
        public
    {
        amount = bound(amount, 1, SUPPLY);
        approved = bound(approved, amount, type(uint256).max);
        token.approve(spender, approved);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), amount);
        assertEq(token.allowance(address(this), spender), approved);
        _assertBalances(0, 0);

        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, amount));
        assertEq(token.allowance(address(this), spender), approved == type(uint256).max ? approved : approved - amount);
        _assertBalances(amount, 0);
    }

    function testFuzz_ReturningTokensDoesNotRestoreSpentAllowance(uint256 amount) public {
        amount = bound(amount, 1, SUPPLY);
        token.approve(spender, amount);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, amount));
        vm.prank(alice);
        assertTrue(token.transfer(address(this), amount));
        assertEq(token.allowance(address(this), spender), 0);
        _assertBalances(0, 0);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.allowance(address(this), spender), 0);
        _assertBalances(0, 0);
    }

    function testFuzz_SplitSpendingEqualsSingleSpending(uint256 approved, uint256 total, uint256 first) public {
        approved = bound(approved, 0, type(uint256).max - 1);
        total = bound(total, 0, approved < SUPPLY ? approved : SUPPLY);
        first = bound(first, 0, total);
        SoothToken single = new SoothToken();
        token.approve(spender, approved);
        single.approve(spender, approved);

        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, first));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, total - first));
        vm.prank(spender);
        assertTrue(single.transferFrom(address(this), alice, total));

        assertEq(token.balanceOf(address(this)), single.balanceOf(address(this)));
        assertEq(token.balanceOf(alice), single.balanceOf(alice));
        assertEq(token.allowance(address(this), spender), single.allowance(address(this), spender));
        assertEq(token.allowance(address(this), spender), approved - total);
        _assertBalances(total, 0);
    }

    function _assertBalances(uint256 aliceBalance, uint256 bobBalance) private view {
        assertEq(token.balanceOf(alice), aliceBalance);
        assertEq(token.balanceOf(bob), bobBalance);
        assertEq(token.balanceOf(address(this)), SUPPLY - aliceBalance - bobBalance);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
