// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

import {TestUtils} from "test/utils/TestUtils.sol";
import {MockUSDC} from "test/mock/MockUSDC.sol";
import {CrateFactoryV2} from "src/CrateFactoryV2.sol";
import {CrateTokenV2} from "src/CrateTokenV2.sol";
import {ICrateV2} from "src/interfaces/ICrateV2.sol";

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
        // pass the fork rpc url in the test like so forge test --fork-url [rpc-url]

        vm.deal(artist, 1000 ether);
        vm.deal(alice, 1000 ether);
        vm.deal(bob, 1000 ether);
        deal(usdc, bob, 100_000 * 1e6);
        deal(usdc, artist, 100_000 * 1e6);

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

    function testWithdrawArtistFees() public {
        vm.startPrank(bob);
        IERC20(usdc).approve(address(token), 100_000 * 1e6);

        token.fund(5000 * 1e6);
        vm.stopPrank();

        assertGt(token.artistCrowdfundFees(), 0, "Artist did not accumulate fees");
        uint256 initialArtistBalance = IERC20(usdc).balanceOf(artist);

        vm.startPrank(artist);
        token.withdrawArtistFees();

        uint256 finalArtistBalance = IERC20(usdc).balanceOf(artist);
        assertEq(finalArtistBalance, initialArtistBalance + 4500 * 1e6, "Artist did not receive the correct USDC");

        assertEq(token.artistCrowdfundFees(), 0, "Artist fees should be reset to zero");
        vm.stopPrank();
    }

    function testFail_WithdrawArtistFees_WrongPhase() public {
        vm.startPrank(bob);

        IERC20(usdc).approve(address(token), 100_000 * 1e6);
        token.fund(4000 * 1e6);
        vm.stopPrank();
        vm.startPrank(artist);
        token.withdrawArtistFees();
        vm.stopPrank();
    }

    function testFail_WithdrawArtistFees_WrongUser() public {
        vm.startPrank(bob);
        IERC20(usdc).approve(address(token), 100_000 * 1e6);
        token.fund(5000 * 1e6);
        token.withdrawArtistFees();
        vm.stopPrank();
    }

    // function testEndBondingCurveAndAddLiquidity() public prank(bob) {
    //     token.buy{value: 8 ether}(80_000 * 1e18); // Buy out the curve
    //     assert(token.phase() == Phase.MARKET);
    //     assertGt(address(token).balance, 0);
    // }
}
