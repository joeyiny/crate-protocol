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
        address tokenAddress = address(factory.createToken{value: 0.00125 ether}(name, symbol, songURI, salt));
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
        address tokenAddress = address(factory.createToken{value: 0.00125 ether}(name, symbol, songURI, salt));
        CrateTokenV2 token2 = CrateTokenV2(tokenAddress);

        assertEq(token2.name(), name);
        assertEq(token2.symbol(), symbol);
        assertEq(token2.totalSupply(), 117_000 * 1e18);
    }

    function testFuzz_Donation(uint256 usdcAmount) public prank(bob) {
        uint256 initialUserBalance = IERC20(usdc).balanceOf(bob);
        usdcAmount = bound(usdcAmount, 1 * 1e6, 1000 * 1e6);
        IERC20(usdc).approve(address(token), usdcAmount);

        token.fund(usdcAmount);

        assertEq(IERC20(usdc).balanceOf(bob), initialUserBalance - usdcAmount, "Bob should have usdc balance deducted");
        assertEq(IERC20(usdc).balanceOf(address(token)), 0, "token contract should have not have any usdc");
        assertTrue(
            IERC20(usdc).balanceOf(address(factory)) == (usdcAmount / 10),
            "protocol fee address should have earned 10% usdc"
        );
        assertTrue(
            IERC20(usdc).balanceOf(address(artist)) == (usdcAmount - (usdcAmount / 10)),
            "artist should have received 90% usdc"
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
    }

    function testFuzz_CompleteCrowdfund() public prank(bob) {
        assertTrue(token.phase() == Phase.CROWDFUND, "Should start in crowdfund phase");

        IERC20(usdc).approve(address(token), 100_000 * 1e6);

        token.fund(3000 * 1e6);

        assertTrue(token.phase() == Phase.CROWDFUND, "Should still be in crowdfund phase");

        token.fund(2000 * 1e6);

        assertTrue(token.phase() == Phase.BONDING_CURVE, "Should now be in bonding curve phase");
    }

    function testFailFuzz_Donation(uint256 usdcAmount) public prank(bob) {
        usdcAmount = bound(usdcAmount, 1, 999_999); // Less than $1 in USDC
        IERC20(usdc).approve(address(token), usdcAmount);
        token.fund(usdcAmount);
    }

    function testFuzz_BuyWithEth(uint256 ethAmount) public prank(alice) {
        ethAmount = bound(ethAmount, 0.001 ether, 4 ether);
        token.buyWithEth{value: ethAmount}(0);
        assertGt(token.balanceOf(alice), 0);
    }

    function testFuzz_Buy(uint256 tokenAmount) public prank(bob) {
        tokenAmount = bound(tokenAmount, 1e18, 1e21);
        token.buy{value: 1000 ether}(tokenAmount);
        assertTrue(token.balanceOf(bob) == tokenAmount);
    }

    function testfuzz_Sell_BondingCurve_One(uint256 buyAmount) public prank(bob) {
        buyAmount = bound(buyAmount, 20_001e18, 79_000e18);
        /// Purchase out the crowdfund
        token.buy{value: 1000 ether}(buyAmount);
        token.sell(token.balanceOf(bob) - 20_000e18, 0);
        assertEq(token.balanceOf(bob), 20_000e18);
    }

    function testfuzz_Sell_BondingCurve_Two(uint256 buyAmount) public prank(bob) {
        buyAmount = bound(buyAmount, 20_001e18, 69_000e18);
        /// Purchase out the crowdfund
        token.buy{value: 100 ether}(buyAmount);
        uint256 buyAmountTwo = 10_000e18;
        token.buy{value: 100 ether}(buyAmountTwo);
        token.sell(token.balanceOf(bob) - 20_000e18, 0);
        assertEq(token.balanceOf(bob), 20_000e18);
        assertEq(token.crowdfund(bob), 20_000e18);
    }

    function testfuzz_Sell_BondingCurve_Three(uint256 buyAmount) public prank(bob) {
        buyAmount = bound(buyAmount, 20_001e18, 79_000e18);
        /// Purchase out the crowdfund
        token.buy{value: 1000 ether}(buyAmount);
        /// Unable to sell crowdfund tokens
        vm.expectRevert(InsufficientTokens.selector);
        token.sell(buyAmount, 0);
        /// Unable to transfer tokens also
        vm.expectRevert(WrongPhase.selector);
        token.transfer(alice, buyAmount);
    }

    function testfuzz_Sell_Crowdfund(uint256 buyAmount) public prank(bob) {
        buyAmount = bound(buyAmount, 1e18, 19_999e18);
        token.buy{value: 1000 ether}(buyAmount);
        uint256 amountToSell = token.balanceOf(bob);
        vm.expectRevert(WrongPhase.selector);
        token.sell(amountToSell, 0);
        assertEq(token.crowdfund(bob), buyAmount);
    }
}
