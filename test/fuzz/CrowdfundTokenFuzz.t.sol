// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

import {TestUtils} from "test/utils/TestUtils.sol";
import {MockUSDC} from "test/mock/MockUSDC.sol";
import {TokenFactory} from "src/TokenFactory.sol";
import {CrowdfundToken} from "src/CrowdfundToken.sol";
import {ICrateV2} from "src/interfaces/ICrateV2.sol";
import {console} from "forge-std/console.sol";

/// @dev forge test --match-contract CrowdfundTokenTest -vvv
contract CrowdfundTokenTest is TestUtils, ICrateV2 {
    TokenFactory factory;
    CrowdfundToken token;
    address uniswapRouter = 0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24; //Router on Base
    address usdc = address(new MockUSDC());
    address artist = address(0x420);
    address owner = address(0xb39);
    address alice = address(0x123);
    address bob = address(0x456);
    // address protocolFeeAddress = address(0x789);
    address artistAddress = address(0xabc);

    function setUp() public {
        vm.deal(artist, 1 ether);
        vm.deal(owner, 1000 ether);
        vm.deal(alice, 1 ether);
        vm.deal(bob, 1 ether);
        deal(usdc, bob, 10_000_000 * 1e6);
        deal(usdc, alice, 100_000 * 1e6);
        deal(usdc, artist, 100_000 * 1e6);

        vm.startPrank(owner);
        factory = new TokenFactory(usdc,19e6);
        vm.stopPrank();
        vm.startPrank(artist);

        string memory name = "TestToken";
        string memory symbol = "TTK";
        string memory songURI = "example.com";
        bytes32 salt = keccak256(abi.encode(name, symbol, songURI));

        IERC20(usdc).approve(address(factory), factory.launchCost());
        address tokenAddress = address(factory.createToken(name, symbol, songURI, salt, 5000e6));
        token = CrowdfundToken(tokenAddress);
        vm.stopPrank();
    }

    function testFuzz_InitialSetup(string memory name, string memory symbol, string memory songURI)
        public
        prank(alice)
    {
        vm.assume(bytes(name).length > 0);
        vm.assume(bytes(symbol).length > 0);
        vm.assume(bytes(songURI).length > 0);

        bytes32 salt = keccak256(abi.encode(name, symbol, songURI));
        IERC20(usdc).approve(address(factory), factory.launchCost());
        address tokenAddress = address(factory.createToken(name, symbol, songURI, salt, 5000e6));
        CrowdfundToken token2 = CrowdfundToken(tokenAddress);

        assertEq(token2.name(), name);
        assertEq(token2.symbol(), symbol);
    }

    function testFuzz_Donation(uint256 usdcAmount) public prank(bob) {
        uint256 initialUserBalance = IERC20(usdc).balanceOf(bob);
        usdcAmount = bound(usdcAmount, 1 * 1e6, 1000 * 1e6);
        uint256 numTokens = token.calculateTokenPurchaseAmount(usdcAmount);
        IERC20(usdc).approve(address(token), usdcAmount);

        vm.expectEmit(true, true, true, true);
        emit ICrateV2.Fund(address(bob), usdcAmount, numTokens);
        token.fund(usdcAmount);
        assertTrue(token.amountPaid(bob) == (usdcAmount));

        assertEq(IERC20(usdc).balanceOf(bob), initialUserBalance - usdcAmount, "Bob should have usdc balance deducted");
        assertTrue(
            token.protocolCrowdfundFees() == (usdcAmount / 10), "protocol fee address should have earned 10% usdc"
        );
        assertTrue(
            token.artistCrowdfundFees() == (usdcAmount - (usdcAmount / 10)),
            "artist fees should have accumulated by 90%"
        );
        assertTrue(token.balanceOf(bob) == (usdcAmount * 1e18) / (5 * 1e6), "user should have earned tokens");
    }

    function test_RevertWhen_DonationDuringWrongPhase() public prank(bob) {
        IERC20(usdc).approve(address(token), 10_000e6);
        token.fund(5000e6); //sell out the curve
        vm.expectRevert("Incorrect phase");
        token.fund(1);
    }

    function testFuzz_CompleteCrowdfund() public {
        vm.startPrank(bob);
        assertTrue(token.phase() == Phase.CROWDFUND, "Should start in crowdfund phase");

        IERC20(usdc).approve(address(token), 100_000 * 1e6);

        token.fund(3000 * 1e6);

        assertTrue(token.phase() == Phase.CROWDFUND, "Should still be in crowdfund phase");

        token.fund(2000 * 1e6);

        assertTrue(token.phase() == Phase.PENDING, "Should now be in pending phase");
        assertTrue(token.balanceOf(bob) == (1000 * 1e18));
        assertTrue(token.crowdfundTokens(bob) == (1000 * 1e18));
        vm.stopPrank();
        vm.startPrank(owner);
        factory.approveTokenCrowdfund(address(token));
        assertTrue(token.phase() == Phase.COMPLETED, "Should now be in bonding curve phase");
        vm.stopPrank();
    }

    function test_CancelCrowdfund() public {
        // Bob participates in the crowdfund
        vm.startPrank(bob);
        uint256 initialUserBalance = IERC20(usdc).balanceOf(bob);
        IERC20(usdc).approve(address(token), 100_000 * 1e6);
        token.fund(3000 * 1e6);
        vm.stopPrank();

        assertTrue(token.phase() == Phase.CROWDFUND, "Should be in crowdfund phase");

        // Confirm Bob's participation and balances before cancellation
        assertEq(token.amountPaid(bob), 3000 * 1e6, "Bob's amount paid should be 3000 USDC");
        assertTrue(token.crowdfundTokens(bob) > 0, "Bob should have received crowdfund tokens");

        // Now cancel the crowdfund
        vm.prank(artist);
        token.cancelCrowdfund();
        assertTrue(token.phase() == Phase.CANCELED, "Phase should be CANCELED after cancelCrowdfund");

        // Bob claims refund
        vm.startPrank(bob);
        token.claimRefund();
        vm.stopPrank();

        // Check that Bob's USDC was refunded correctly
        assertEq(IERC20(usdc).balanceOf(bob), initialUserBalance, "Bob should have received a full USDC refund");

        // Verify that Bob's tokens were burned
        assertEq(token.balanceOf(bob), 0, "Bob's tokens should be burned");

        // Ensure the protocol and artist fees are reset to zero
        assertEq(token.protocolCrowdfundFees(), 0, "Protocol fees should be reset to zero");
        assertEq(token.artistCrowdfundFees(), 0, "Artist fees should be reset to zero");

        // Verify internal state reset for Bob
        assertEq(token.amountPaid(bob), 0, "Bob's amountPaid should be reset to zero");
        assertEq(token.crowdfundTokens(bob), 0, "Bob's crowdfundTokens should be reset to zero");
    }

    function test_CancelCrowdfundFail_WrongPhase() public {
        // First fund enough to move out of crowdfund phase
        vm.startPrank(bob);
        IERC20(usdc).approve(address(token), 100_000 * 1e6);
        token.fund(5000 * 1e6); // This moves us to bonding curve phase
        vm.stopPrank();

        // Verify we're in bonding curve phase
        assertEq(uint256(token.phase()), uint256(Phase.PENDING), "Should be in pending phase");

        vm.startPrank(owner);
        factory.approveTokenCrowdfund(address(token));
        vm.stopPrank();
        // Try to cancel crowdfund - should fail
        vm.startPrank(artist);
        vm.expectRevert("This token is not in the correct phase, cannot cancel.");
        token.cancelCrowdfund();
        vm.stopPrank();

        // Verify we're still in bonding curve phase
        assertEq(uint256(token.phase()), uint256(Phase.COMPLETED), "Should still be in bonding curve phase");
    }

    function test_CancelCrowdfund_MultipleUsers() public {
        address charlie = address(0x789);

        // Set up initial USDC balances for users
        deal(usdc, alice, 50_000 * 1e6);
        deal(usdc, bob, 50_000 * 1e6);
        deal(usdc, charlie, 50_000 * 1e6);

        // Allow all users to approve the token contract for USDC transfers
        vm.startPrank(alice);
        IERC20(usdc).approve(address(token), 50_000 * 1e6);
        vm.stopPrank();

        vm.startPrank(bob);
        IERC20(usdc).approve(address(token), 50_000 * 1e6);
        vm.stopPrank();

        vm.startPrank(charlie);
        IERC20(usdc).approve(address(token), 50_000 * 1e6);
        vm.stopPrank();

        // Multiple transactions from each user
        vm.startPrank(alice);
        token.fund(200 * 1e6);
        vm.stopPrank();

        vm.startPrank(bob);
        token.fund(1210 * 1e6);
        token.fund(12 * 1e6);
        vm.stopPrank();

        vm.startPrank(alice);
        token.fund(9 * 1e6);
        vm.stopPrank();

        vm.startPrank(bob);
        token.fund(12 * 1e6);
        vm.stopPrank();

        vm.startPrank(charlie);
        token.fund(10 * 1e6);
        vm.stopPrank();

        vm.startPrank(alice);
        token.fund(9 * 1e6);
        vm.stopPrank();

        // Check initial balances and state before cancellation
        assertEq(
            token.balanceOf(alice),
            token.calculateTokenPurchaseAmount(218 * 1e6),
            "Alice's token balance should be correct before cancellation"
        );
        assertEq(
            token.balanceOf(bob),
            token.calculateTokenPurchaseAmount(1234 * 1e6),
            "Bob's token balance should be correct before cancellation"
        );
        assertEq(
            token.balanceOf(charlie),
            token.calculateTokenPurchaseAmount(10 * 1e6),
            "Charlie's token balance should be correct before cancellation"
        );

        assertEq(token.amountPaid(alice), 218 * 1e6, "Alice's amountPaid should be correct before cancellation");
        assertEq(token.amountPaid(bob), 1234 * 1e6, "Bob's amountPaid should be correct before cancellation");
        assertEq(token.amountPaid(charlie), 10 * 1e6, "Charlie's amountPaid should be correct before cancellation");

        assertEq(
            token.crowdfundTokens(alice),
            token.calculateTokenPurchaseAmount(218 * 1e6),
            "Alice's crowdfundTokens should be correct before cancellation"
        );
        assertEq(
            token.crowdfundTokens(bob),
            token.calculateTokenPurchaseAmount(1234 * 1e6),
            "Bob's crowdfundTokens should be correct before cancellation"
        );
        assertEq(
            token.crowdfundTokens(charlie),
            token.calculateTokenPurchaseAmount(10 * 1e6),
            "Charlie's crowdfundTokens should be correct before cancellation"
        );

        assertEq(
            token.protocolCrowdfundFees(),
            (1234 * 1e6 + 218 * 1e6 + 10 * 1e6) * 10 / 100,
            "Protocol fees should be correct before cancellation"
        );
        assertEq(
            token.artistCrowdfundFees(),
            (1234 * 1e6 + 218 * 1e6 + 10 * 1e6) * 90 / 100,
            "Artist fees should be correct before cancellation"
        );

        // Cancel the crowdfund
        vm.prank(artist);
        token.cancelCrowdfund();

        // Users attempt to claim refunds
        vm.startPrank(alice);
        token.claimRefund();
        vm.stopPrank();

        vm.startPrank(bob);
        token.claimRefund();
        vm.stopPrank();

        vm.startPrank(charlie);
        token.claimRefund();
        vm.stopPrank();

        // Check that all users have been refunded their USDC and their tokens have been burned
        assertEq(IERC20(usdc).balanceOf(alice), 50_000 * 1e6, "Alice should have received a full USDC refund");
        assertEq(IERC20(usdc).balanceOf(bob), 50_000 * 1e6, "Bob should have received a full USDC refund");
        assertEq(IERC20(usdc).balanceOf(charlie), 50_000 * 1e6, "Charlie should have received a full USDC refund");

        // Ensure that all users' tokens have been burned
        assertEq(token.balanceOf(alice), 0, "Alice's tokens should be burned");
        assertEq(token.balanceOf(bob), 0, "Bob's tokens should be burned");
        assertEq(token.balanceOf(charlie), 0, "Charlie's tokens should be burned");

        // Verify the protocol and artist fees are reset to zero
        assertEq(token.protocolCrowdfundFees(), 0, "Protocol fees should be reset to zero");
        assertEq(token.artistCrowdfundFees(), 0, "Artist fees should be reset to zero");

        // Ensure internal state is reset for each user
        assertEq(token.amountPaid(alice), 0, "Alice's amountPaid should be reset to zero");
        assertEq(token.crowdfundTokens(alice), 0, "Alice's crowdfundTokens should be reset to zero");

        assertEq(token.amountPaid(bob), 0, "Bob's amountPaid should be reset to zero");
        assertEq(token.crowdfundTokens(bob), 0, "Bob's crowdfundTokens should be reset to zero");

        assertEq(token.amountPaid(charlie), 0, "Charlie's amountPaid should be reset to zero");
        assertEq(token.crowdfundTokens(charlie), 0, "Charlie's crowdfundTokens should be reset to zero");
    }

    function test_RevertWhen_ClaimRefund_NotCanceled() public {
        // Bob tries to claim refund before crowdfund is canceled
        vm.startPrank(bob);
        vm.expectRevert("Crowdfund not canceled");
        token.claimRefund();
        vm.stopPrank();
    }

    function test_RevertWhen_ClaimRefund_Twice() public {
        // Bob participates in the crowdfund
        vm.startPrank(bob);
        IERC20(usdc).approve(address(token), 100_000 * 1e6);
        token.fund(3000 * 1e6);
        vm.stopPrank();

        // Cancel the crowdfund
        vm.prank(artist);
        token.cancelCrowdfund();

        // Bob claims refund
        vm.startPrank(bob);
        token.claimRefund();
        // Bob tries to claim refund again (should fail)
        vm.expectRevert("Refund already claimed");
        token.claimRefund();
        vm.stopPrank();
    }

    function test_RevertWhen_ClaimRefund_NoFunds() public {
        // Alice did not participate in the crowdfund
        vm.startPrank(artist);
        IERC20(usdc).approve(address(token), 1000e6);
        token.fund(1000e6);
        token.cancelCrowdfund();
        vm.stopPrank();

        // Alice tries to claim refund (should fail)
        vm.startPrank(alice);
        vm.expectRevert("No funds to refund");
        token.claimRefund();
        vm.stopPrank();
    }

    function test_RevertWhen_CancelCrowdfund_NoAuth() public {
        vm.startPrank(alice);
        IERC20(usdc).approve(address(token), 100_000 * 1e6);

        token.fund(200 * 1e6);
        vm.expectRevert("Not authorized.");
        token.cancelCrowdfund();
        vm.stopPrank();
    }

    function test_CancelCrowdfund_ProtocolAuth() public {
        vm.startPrank(bob);
        IERC20(usdc).approve(address(token), 100_000 * 1e6);
        token.fund(200 * 1e6);
        vm.stopPrank();
        vm.startPrank(owner);
        factory.cancelTokenCrowdfund(address(token));
        vm.stopPrank();
    }

    function test_RevertWhen_CancelCrowdfund_WrongPhase() public {
        vm.startPrank(artist);

        // Transition the phase to COMPLETED to simulate an active phase
        IERC20(usdc).approve(address(token), 100_000 * 1e6);
        token.fund(5000 * 1e6);
        vm.stopPrank();
        vm.startPrank(owner);
        factory.approveTokenCrowdfund(address(token));
        vm.stopPrank();
        vm.startPrank(artist);
        vm.expectRevert("This token is not in the correct phase, cannot cancel.");
        token.cancelCrowdfund();
        vm.stopPrank();
    }
}
