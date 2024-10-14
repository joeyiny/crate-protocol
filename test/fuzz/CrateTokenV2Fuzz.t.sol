// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

import {TestUtils} from "test/utils/TestUtils.sol";
import {MockUSDC} from "test/mock/MockUSDC.sol";
import {CrateFactoryV2} from "src/CrateFactoryV2.sol";
import {CrateTokenV2} from "src/CrateTokenV2.sol";
import {ICrateV2} from "src/interfaces/ICrateV2.sol";
import {console} from "forge-std/console.sol";

/// @dev forge test --match-contract CrateTokenV2Test -vvv
contract CrateTokenV2Test is TestUtils, ICrateV2 {
    CrateFactoryV2 factory;
    CrateTokenV2 token;
    address uniswapRouter = 0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24; //Router on Base
    // address usdc = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913; //USDC on Base
    address usdc = address(new MockUSDC());
    address artist = address(0x420);
    address alice = address(0x123);
    address bob = address(0x456);
    // address protocolFeeAddress = address(0x789);
    address artistAddress = address(0xabc);

    function setUp() public {
        vm.deal(artist, 1000 ether);
        vm.deal(alice, 1000 ether);
        vm.deal(bob, 1000 ether);
        deal(usdc, bob, 100_000 * 1e6);

        vm.startPrank(artist);
        factory = new CrateFactoryV2(uniswapRouter, usdc);
        string memory name = "TestToken";
        string memory symbol = "TTK";
        string memory songURI = "example.com";
        bytes32 salt = keccak256(abi.encode(name, symbol, songURI));
        address tokenAddress = address(factory.createToken{value: 0.04 ether}(name, symbol, songURI, salt));
        token = CrateTokenV2(tokenAddress);
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
        address tokenAddress = address(factory.createToken{value: 0.04 ether}(name, symbol, songURI, salt));
        CrateTokenV2 token2 = CrateTokenV2(tokenAddress);

        assertEq(token2.name(), name);
        assertEq(token2.symbol(), symbol);
        assertEq(token2.totalSupply(), 117_000 * 1e18);
    }

    function testFuzz_Donation(uint256 usdcAmount) public prank(bob) {
        uint256 initialUserBalance = IERC20(usdc).balanceOf(bob);
        usdcAmount = bound(usdcAmount, 1 * 1e6, 1000 * 1e6);
        uint256 numTokens = token.calculateTokenAmount(usdcAmount);
        IERC20(usdc).approve(address(token), usdcAmount);

        vm.expectEmit(true, true, true, true);
        emit ICrateV2.Fund(address(bob), usdcAmount, numTokens);
        token.fund(usdcAmount);
        assertTrue(token.amountPaid(bob) == (usdcAmount));

        assertEq(IERC20(usdc).balanceOf(bob), initialUserBalance - usdcAmount, "Bob should have usdc balance deducted");
        // assertEq(IERC20(usdc).balanceOf(address(token)), 0, "token contract should have not have any usdc");
        assertTrue(token.protocolFees() == (usdcAmount / 10), "protocol fee address should have earned 10% usdc");
        assertTrue(
            token.artistCrowdfundFees() == (usdcAmount - (usdcAmount / 10)),
            "artist fees should have accumulated by 90%"
        );
        assertTrue(token.balanceOf(bob) == (usdcAmount * 1e18) / (5 * 1e6), "user should have earned tokens");
    }

    function testFuzz_CompleteCrowdfund() public prank(bob) {
        assertTrue(token.phase() == Phase.CROWDFUND, "Should start in crowdfund phase");

        IERC20(usdc).approve(address(token), 100_000 * 1e6);

        token.fund(3000 * 1e6);

        assertTrue(token.phase() == Phase.CROWDFUND, "Should still be in crowdfund phase");

        token.fund(2000 * 1e6);

        assertTrue(token.phase() == Phase.BONDING_CURVE, "Should now be in bonding curve phase");
        assertTrue(token.balanceOf(bob) == (1000 * 1e18));
        assertTrue(token.crowdfundTokens(bob) == (1000 * 1e18));
    }

    function test_CancelCrowdfund() public prank(bob) {
        // Approve the contract to transfer USDC on behalf of the user (bob)
        IERC20(usdc).approve(address(token), 100_000 * 1e6);

        // Fund the crowdfund partially to set up state
        token.fund(3000 * 1e6);
        assertTrue(token.phase() == Phase.CROWDFUND, "Should be in crowdfund phase");

        // Confirm bob's participation and balances before cancellation
        assertTrue(token.amountPaid(bob) == 3000 * 1e6, "Bob's amount paid should be 3000 USDC");
        assertTrue(token.crowdfundTokens(bob) > 0, "Bob should have received crowdfund tokens");

        // Now cancel the crowdfund
        token.cancelCrowdfund();
        assertTrue(token.phase() == Phase.CANCELED, "Phase should be CANCELED after cancelCrowdfund");

        // Check that Bob's USDC was refunded correctly
        assertEq(IERC20(usdc).balanceOf(bob), 100_000 * 1e6, "Bob should have received a full USDC refund");

        // Verify that Bob's tokens were burned
        assertEq(token.balanceOf(bob), 0, "Bob's tokens should be burned");

        // Ensure the protocol and artist fees are reset to zero
        assertEq(token.protocolFees(), 0, "Protocol fees should be reset to zero");
        assertEq(token.artistFees(), 0, "Artist fees should be reset to zero");

        // Verify internal state reset for Bob
        assertEq(token.amountPaid(bob), 0, "Bob's amountPaid should be reset to zero");
        assertEq(token.crowdfundTokens(bob), 0, "Bob's crowdfundTokens should be reset to zero");
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
        // token.fund(1000 * 1e6);
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

        // Cancel the crowdfund
        token.cancelCrowdfund();

        // Check that all users have been refunded their USDC and their tokens have been burned
        assertEq(IERC20(usdc).balanceOf(alice), 50_000 * 1e6, "Alice should have received a full USDC refund");
        assertEq(IERC20(usdc).balanceOf(bob), 50_000 * 1e6, "Bob should have received a full USDC refund");
        assertEq(IERC20(usdc).balanceOf(charlie), 50_000 * 1e6, "Charlie should have received a full USDC refund");

        // Ensure that all users' tokens have been burned
        assertEq(token.balanceOf(alice), 0, "Alice's tokens should be burned");
        assertEq(token.balanceOf(bob), 0, "Bob's tokens should be burned");
        assertEq(token.balanceOf(charlie), 0, "Charlie's tokens should be burned");

        // Verify the protocol and artist fees are reset to zero
        assertEq(token.protocolFees(), 0, "Protocol fees should be reset to zero");
        assertEq(token.artistFees(), 0, "Artist fees should be reset to zero");

        // Ensure internal state is reset for each user
        assertEq(token.amountPaid(alice), 0, "Alice's amountPaid should be reset to zero");
        assertEq(token.crowdfundTokens(alice), 0, "Alice's crowdfundTokens should be reset to zero");

        assertEq(token.amountPaid(bob), 0, "Bob's amountPaid should be reset to zero");
        assertEq(token.crowdfundTokens(bob), 0, "Bob's crowdfundTokens should be reset to zero");

        assertEq(token.amountPaid(charlie), 0, "Charlie's amountPaid should be reset to zero");
        assertEq(token.crowdfundTokens(charlie), 0, "Charlie's crowdfundTokens should be reset to zero");
    }

    function testFail_CancelCrowdfund_NotInCrowdfundPhase() public {
        // Transition the phase to BONDING_CURVE to simulate an active phase
        IERC20(usdc).approve(address(token), 100_000 * 1e6);
        token.fund(5000 * 1e6); // Reaching the crowdfund goal to move to the BONDING_CURVE phase

        // Attempt to cancel crowdfund in BONDING_CURVE phase, which should revert
        token.cancelCrowdfund();
    }

    // function testFailFuzz_Donation(uint256 usdcAmount) public prank(bob) {
    //     usdcAmount = bound(usdcAmount, 1, 999_999); // Less than $1 in USDC
    //     IERC20(usdc).approve(address(token), usdcAmount);
    //     token.fund(usdcAmount);
    // }

    // function testFuzz_BuyWithEth(uint256 ethAmount) public prank(alice) {
    //     ethAmount = bound(ethAmount, 0.001 ether, 4 ether);
    //     token.buyWithEth{value: ethAmount}(0);
    //     assertGt(token.balanceOf(alice), 0);
    // }

    // function testFuzz_Buy(uint256 tokenAmount) public prank(bob) {
    //     tokenAmount = bound(tokenAmount, 1e18, 1e21);
    //     token.buy{value: 1000 ether}(tokenAmount);
    //     assertTrue(token.balanceOf(bob) == tokenAmount);
    // }

    // function testfuzz_Sell_BondingCurve_One(uint256 buyAmount) public prank(bob) {
    //     buyAmount = bound(buyAmount, 20_001e18, 79_000e18);
    //     /// Purchase out the crowdfund
    //     token.buy{value: 1000 ether}(buyAmount);
    //     token.sell(token.balanceOf(bob) - 20_000e18, 0);
    //     assertEq(token.balanceOf(bob), 20_000e18);
    // }

    // function testfuzz_Sell_BondingCurve_Two(uint256 buyAmount) public prank(bob) {
    //     buyAmount = bound(buyAmount, 20_001e18, 69_000e18);
    //     /// Purchase out the crowdfund
    //     token.buy{value: 100 ether}(buyAmount);
    //     uint256 buyAmountTwo = 10_000e18;
    //     token.buy{value: 100 ether}(buyAmountTwo);
    //     token.sell(token.balanceOf(bob) - 20_000e18, 0);
    //     assertEq(token.balanceOf(bob), 20_000e18);
    //     assertEq(token.crowdfund(bob), 20_000e18);
    // }

    // function testfuzz_Sell_BondingCurve_Three(uint256 buyAmount) public prank(bob) {
    //     buyAmount = bound(buyAmount, 20_001e18, 79_000e18);
    //     /// Purchase out the crowdfund
    //     token.buy{value: 1000 ether}(buyAmount);
    //     /// Unable to sell crowdfund tokens
    //     vm.expectRevert(InsufficientTokens.selector);
    //     token.sell(buyAmount, 0);
    //     /// Unable to transfer tokens also
    //     vm.expectRevert(WrongPhase.selector);
    //     token.transfer(alice, buyAmount);
    // }

    // function testfuzz_Sell_Crowdfund(uint256 buyAmount) public prank(bob) {
    //     buyAmount = bound(buyAmount, 1e18, 19_999e18);
    //     token.buy{value: 1000 ether}(buyAmount);
    //     uint256 amountToSell = token.balanceOf(bob);
    //     vm.expectRevert(WrongPhase.selector);
    //     token.sell(amountToSell, 0);
    //     assertEq(token.crowdfund(bob), buyAmount);
    // }
}
