// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TestUtils} from "test/utils/TestUtils.sol";
import {CrateFactoryV2} from "src/CrateFactoryV2.sol";
import {CrateTokenV2} from "src/CrateTokenV2.sol";
import {ICrateV2} from "src/interfaces/ICrateV2.sol";

contract CrateTokenV2Test is TestUtils, ICrateV2 {
    CrateFactoryV2 factory;
    CrateTokenV2 token;
    address uniswapRouter = 0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24; //Router on Base
    address base = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913; //USDC on Base

    address owner = address(0x420);
    address alice = address(0x123);
    address bob = address(0x456);
    address protocolFeeAddress = address(0x789);
    address artistAddress = address(0xabc);

    function setUp() public {
        uint256 baseFork = vm.createFork("https://1rpc.io/base");
        vm.selectFork(baseFork);

        vm.deal(owner, 1000 ether);
        vm.deal(alice, 1000 ether);
        vm.deal(bob, 1000 ether);

        vm.startPrank(owner);
        factory = new CrateFactoryV2(uniswapRouter, base);
        string memory name = "TestToken";
        string memory symbol = "TTK";
        string memory songURI = "example.com";
        bytes32 salt = keccak256(abi.encode(name, symbol, songURI));
        address tokenAddress = address(
            factory.createToken{value: 0.00125 ether}(
                name,
                symbol,
                songURI,
                salt
            )
        );
        token = CrateTokenV2(tokenAddress);
        vm.stopPrank();
    }

    function testEndBondingCurveAndAddLiquidity() public prank(bob) {
        token.buy{value: 8 ether}(80_000 * 1e18); // Buy out the curve
        assert(token.phase() == Phase.MARKET);
        assertGt(address(token).balance, 0);
    }
}
