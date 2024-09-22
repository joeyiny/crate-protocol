// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TestUtils} from "test/utils/TestUtils.sol";
import "src/CrateFactoryV1.sol";

/// @dev forge test --match-contract CrateTokenV1Test -vvv
contract CrateTokenV1Test is TestUtils {
    CrateFactoryV1 factory;
    CrateTokenV1 token;
    address uniswapRouter = 0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24; //Router on Base

    address owner = address(0x420);
    address alice = address(0x123);
    address bob = address(0x456);
    address protocolFeeAddress = address(0x789);
    address artistAddress = address(0xabc);

    function setUp() public {
        vm.deal(owner, 1000 ether);
        vm.deal(alice, 1000 ether);
        vm.deal(bob, 1000 ether);

        vm.startPrank(owner);
        factory = new CrateFactoryV1(uniswapRouter);
        string memory name = "TestToken";
        string memory symbol = "TTK";
        string memory songURI = "example.com";
        bytes32 salt = keccak256(abi.encode(name, symbol, songURI));
        address tokenAddress = address(factory.createToken{value: 0.00125 ether}(name, symbol, songURI, salt));
        token = CrateTokenV1(tokenAddress);
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
        CrateTokenV1 token2 = CrateTokenV1(tokenAddress);

        assertEq(token2.name(), name);
        assertEq(token2.symbol(), symbol);
        assertEq(token2.totalSupply(), 117_000 * 1e18);
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

    function testfuzz_Sell(uint256 buyAmount, uint256 sellAmount) public prank(bob) {
        buyAmount = bound(buyAmount, 1e20, 1e21);
        sellAmount = bound(sellAmount, 1e18, 1e19);
        token.buy{value: 1000 ether}(buyAmount);
        token.sell(sellAmount, 0);
        assertTrue(token.balanceOf(bob) == buyAmount - sellAmount);
    }
}
