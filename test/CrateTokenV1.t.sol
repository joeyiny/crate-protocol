// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "ds-test/test.sol";
import "../src/CrateFactoryV1.sol";

contract CrateTokenV1Test is DSTest {
    Vm vm = Vm(HEVM_ADDRESS);
    CrateTokenV1 token;
    address uniswapRouter = 0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24; //Router on Base

    address alice = address(0x123);
    address bob = address(0x456);
    address protocolFeeAddress = address(0x789);
    address artistAddress = address(0xabc);

    function setUp() public {
        token = new CrateTokenV1();
        token.initialize(
            uniswapRouter,
            "CrateToken",
            "CTK",
            protocolFeeAddress,
            artistAddress,
            "http://example.com"
        );
        vm.deal(alice, 1000 ether);
        vm.deal(bob, 1000 ether);
    }

    function testFuzz_InitialSetup(
        string memory name,
        string memory symbol,
        string memory songURI
    ) public {
        vm.assume(bytes(name).length > 0);
        vm.assume(bytes(symbol).length > 0);
        vm.assume(bytes(songURI).length > 0);
        CrateTokenV1 token2 = new CrateTokenV1();
        token2.initialize(
            uniswapRouter,
            name,
            symbol,
            protocolFeeAddress,
            artistAddress,
            songURI
        );
        assertEq(token2.name(), name);
        assertEq(token2.symbol(), symbol);
        assertEq(token2.totalSupply(), 100_000 * 1e6);
    }

    function testFuzz_BuyWithEth(uint256 ethAmount) public {
        vm.assume(ethAmount <= 1000 ether);
        vm.assume(ethAmount >= 0.000001 ether);
        vm.startPrank(alice);
        token.buyWithEth{value: ethAmount}();
        vm.stopPrank();
        assertTrue(token.balanceOf(alice) > 0);
    }

    function testFuzz_Buy(uint256 tokenAmount) public {
        vm.assume(tokenAmount >= 1e6);
        vm.assume(tokenAmount <= 80000000000);
        vm.startPrank(bob);
        token.buy{value: 1000 ether}(tokenAmount);
        assertTrue(token.balanceOf(bob) == tokenAmount);
        vm.stopPrank();
    }

    function testfuzz_Sell(uint256 tokenAmount) public {
        vm.assume(tokenAmount <= 79999000000);
        vm.startPrank(bob);
        token.buy{value: 1000 ether}(79999000000);
        token.sell(tokenAmount);
        assertTrue(token.balanceOf(bob) == 79999000000 - tokenAmount);
        vm.stopPrank();
    }

    function testTokensInCurve() public {
        assert(token.tokensInCurve() == 80_000 * 1e6);
        vm.startPrank(bob);
        token.buy{value: 1 ether}(10 * 1e6);
        vm.stopPrank();
        assert(token.tokensInCurve() == 79_990 * 1e6);
    }

    function testEndBondingCurveAndAddLiquidity() public {
        vm.startPrank(bob);
        token.buy{value: 8 ether}(80_000 * 1e6); // Buy out the curve
        vm.stopPrank();
        assertTrue(!token.bondingCurveActive());
        assertEq(address(token).balance, 0);
    }
}
