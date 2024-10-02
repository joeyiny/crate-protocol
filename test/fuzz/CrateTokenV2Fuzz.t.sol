// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TestUtils} from "test/utils/TestUtils.sol";
import {CrateFactoryV2} from "src/CrateFactoryV2.sol";
import {CrateTokenV2} from "src/CrateTokenV2.sol";
import {ICrateV2} from "src/interfaces/ICrateV2.sol";
import {IUniswapV2Router02} from "src/interfaces/IUniswapV2RouterV2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockUSDC, MockUniswapV2Router} from "test/utils/Mocks.sol";

/// @dev forge test --match-contract CrateTokenV2TestFuzz -vvv
contract CrateTokenV2TestFuzz is TestUtils, ICrateV2 {
    address protocolFeeAddress = address(0x789);
    address artistAddress = address(0xabc);

    function setUp() public override {
        super.setUp();

        usdc = new MockUSDC();
        uniswapRouter = new MockUniswapV2Router();

        MockUSDC(address(usdc)).mint(alice, 1_000_000_000e6);
        MockUSDC(address(usdc)).mint(bob, 1_000_000_000e6);
        MockUSDC(address(usdc)).mint(owner, 1_000_000_000e6);

        vm.startPrank(owner);
        factory = new CrateFactoryV2(address(uniswapRouter), address(usdc));
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

    function testFuzz_Buy(uint256 tokenAmount) public prank(bob) {
        tokenAmount = bound(tokenAmount, 1e18, 1e21);
        usdc.approve(address(token), ~uint256(0));
        token.buy(tokenAmount);
        assertTrue(token.balanceOf(bob) == tokenAmount);
    }

    function testFuzz_Sell_BondingCurve_One(uint256 buyAmount) public prank(bob) {
        buyAmount = bound(buyAmount, 20_001e18, 79_000e18);
        /// Purchase out the crowdfund
        usdc.approve(address(token), ~uint256(0));
        token.buy(buyAmount);
        token.sell(token.balanceOf(bob) - 20_000e18, 0);
        assertEq(token.balanceOf(bob), 20_000e18);
    }

    function testFuzz_Sell_BondingCurve_Two(uint256 buyAmount) public prank(bob) {
        buyAmount = bound(buyAmount, 20_001e18, 69_000e18);
        /// Purchase out the crowdfund
        usdc.approve(address(token), ~uint256(0));
        token.buy(buyAmount);
        uint256 buyAmountTwo = 10_000e18;
        token.buy(buyAmountTwo);
        token.sell(token.balanceOf(bob) - 20_000e18, 0);
        assertEq(token.balanceOf(bob), 20_000e18);
        assertEq(token.crowdfund(bob), 20_000e18);
    }

    function testFuzz_Sell_BondingCurve_Three(uint256 buyAmount) public prank(bob) {
        buyAmount = bound(buyAmount, 20_001e18, 79_000e18);
        /// Purchase out the crowdfund
        usdc.approve(address(token), ~uint256(0));
        token.buy(buyAmount);
        /// Unable to sell crowdfund tokens
        vm.expectRevert(InsufficientTokens.selector);
        token.sell(buyAmount, 0);
        /// Unable to transfer tokens also
        vm.expectRevert(WrongPhase.selector);
        token.transfer(alice, buyAmount);
    }

    function testFuzz_Sell_Crowdfund(uint256 buyAmount) public prank(bob) {
        buyAmount = bound(buyAmount, 1e18, 19_999e18);
        usdc.approve(address(token), ~uint256(0));
        token.buy(buyAmount);
        uint256 amountToSell = token.balanceOf(bob);
        vm.expectRevert(WrongPhase.selector);
        token.sell(amountToSell, 0);
        assertEq(token.crowdfund(bob), buyAmount);
    }
}
