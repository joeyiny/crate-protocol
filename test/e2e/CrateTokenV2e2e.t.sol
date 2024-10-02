// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TestUtils, console} from "test/utils/TestUtils.sol";
import {CrateFactoryV2} from "src/CrateFactoryV2.sol";
import {CrateTokenV2} from "src/CrateTokenV2.sol";
import {ICrateV2} from "src/interfaces/ICrateV2.sol";
import {IUniswapV2Router02} from "src/interfaces/IUniswapV2RouterV2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract CrateTokenV2TestE2E is TestUtils, ICrateV2 {
    address protocolFeeAddress = address(0x789);
    address artistAddress = address(0xabc);

    function setUp() public override {
        forkBase();
        super.setUp();

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

    function testEndBondingCurveAndAddLiquidity() public prank(bob) {
        usdc.approve(address(token), ~uint256(0));
        token.buy(80_000e18); // Buy out the curve
        assert(token.phase() == Phase.MARKET);
        assertGt(usdc.balanceOf(address(token)), 0);
    }

    function testCostForOneToken() public prank(bob) {
        usdc.approve(address(token), ~uint256(0));
        uint256 costA = token.getBuyPrice(1e18);
        console.log("Cost A: ", costA);
        token.buy(79_999e18); 
        uint256 costB = token.getBuyPrice(1e18);
        console.log("Cost B: ", costB);
    }
}
