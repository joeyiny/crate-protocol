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
    address owner = address(0x420);
    address alice = address(0x123);
    address bob = address(0x456);
    // address protocolFeeAddress = address(0x789);

    function setUp() public {
        // pass the fork rpc url in the test like so forge test --fork-url [rpc-url]

        vm.deal(owner, 1000 ether);
        vm.deal(alice, 1000 ether);
        vm.deal(bob, 1000 ether);
        deal(usdc, bob, 100_000 * 1e6);
        deal(usdc, owner, 100_000 * 1e6);

        vm.startPrank(owner);
        factory = new CrateFactoryV2(usdc);
        string memory name = "TestToken";
        string memory symbol = "TTK";
        string memory songURI = "example.com";
        bytes32 salt = keccak256(abi.encode(name, symbol, songURI));

        IERC20(usdc).approve(address(factory), factory.launchCost());
        address tokenAddress = address(factory.createToken(name, symbol, songURI, salt, 5000e6));
        token = CrateTokenV2(tokenAddress);
        vm.stopPrank();
    }

    function test_CreateTokenWithValidCrowdfundGoal() public {
        uint256 validGoal = 10_000e6; // $10,000
        vm.startPrank(owner);
        string memory name = "ValidGoalToken";
        string memory symbol = "VGT";
        string memory songURI = "example.com/valid";
        bytes32 salt = keccak256(abi.encode(name, symbol, songURI));
        IERC20(usdc).approve(address(factory), factory.launchCost());

        address tokenAddress = factory.createToken(name, symbol, songURI, salt, validGoal);
        CrateTokenV2 validToken = CrateTokenV2(tokenAddress);
        vm.stopPrank();

        assertEq(validToken.crowdfundGoal(), validGoal);
    }

    function testFail_CreateTokenWithBelowMinCrowdfundGoal() public {
        uint256 invalidGoal = 50e6; // Below $100 minimum
        vm.startPrank(owner);
        string memory name = "BelowMinToken";
        string memory symbol = "BMT";
        string memory songURI = "example.com/belowmin";
        bytes32 salt = keccak256(abi.encode(name, symbol, songURI));
        factory.createToken(name, symbol, songURI, salt, invalidGoal);
        vm.stopPrank();
    }

    function testFail_CreateTokenWithAboveMaxCrowdfundGoal() public {
        uint256 invalidGoal = 200_000e6; // Above $100,000 maximum
        vm.startPrank(owner);
        string memory name = "AboveMaxToken";
        string memory symbol = "AMT";
        string memory songURI = "example.com/abovemax";
        bytes32 salt = keccak256(abi.encode(name, symbol, songURI));
        factory.createToken(name, symbol, songURI, salt, invalidGoal);
        vm.stopPrank();
    }

    function test_OwnerCanUpdateCrowdfundGoalLimits() public {
        vm.startPrank(owner);
        factory.updateCrowdfundGoalLimits(200e6, 999_000e6);
        vm.stopPrank();

        assertEq(factory.minCrowdfundGoal(), 200e6);
        assertEq(factory.maxCrowdfundGoal(), 999_000e6);

        uint256 newValidGoal = 885_000e6;
        vm.startPrank(owner);
        string memory name = "NewGoalToken";
        string memory symbol = "NGT";
        string memory songURI = "example.com/newgoal";
        bytes32 salt = keccak256(abi.encode(name, symbol, songURI));
        IERC20(usdc).approve(address(factory), factory.launchCost());
        address tokenAddress = factory.createToken(name, symbol, songURI, salt, newValidGoal);
        CrateTokenV2 newToken = CrateTokenV2(tokenAddress);
        vm.stopPrank();

        assertEq(newToken.crowdfundGoal(), newValidGoal);
    }

    function test_DonationOverpay() public {
        uint256 userBalance = IERC20(usdc).balanceOf(bob);
        vm.startPrank(bob);
        IERC20(usdc).approve(address(token), 100_000 * 1e6);
        token.fund(20_000e6);
        vm.stopPrank();

        assertEq(
            IERC20(usdc).balanceOf(bob),
            100_000e6 - token.crowdfundGoal(),
            "User should have been refunded overpaid amount"
        );
    }

    function testWithdrawArtistFees() public {
        vm.startPrank(bob);
        IERC20(usdc).approve(address(token), 100_000 * 1e6);

        token.fund(5000 * 1e6);
        vm.stopPrank();

        assertGt(token.artistCrowdfundFees(), 0, "Artist did not accumulate fees");
        uint256 initialArtistBalance = IERC20(usdc).balanceOf(owner);

        vm.startPrank(owner);
        token.withdrawArtistFees();

        uint256 finalArtistBalance = IERC20(usdc).balanceOf(owner);
        assertEq(finalArtistBalance, initialArtistBalance + 4500 * 1e6, "Artist did not receive the correct USDC");

        assertEq(token.artistCrowdfundFees(), 0, "Artist fees should be reset to zero");
        vm.stopPrank();
    }

    function testFail_WithdrawArtistFees_WrongPhase() public {
        vm.startPrank(bob);

        IERC20(usdc).approve(address(token), 100_000 * 1e6);
        token.fund(4000 * 1e6);
        vm.stopPrank();
        vm.startPrank(owner);
        token.withdrawArtistFees();
        vm.stopPrank();
    }

    function testWithdrawProtocolFees() public {
        assertEq(token.protocolCrowdfundFees(), 0, "Protocol fees should start at 0");
        uint256 protocolFeesToBePaid = token.protocolCrowdfundFees();
        uint256 initialOwnerBalance = IERC20(usdc).balanceOf(owner);

        vm.startPrank(bob);
        IERC20(usdc).approve(address(token), 100_000 * 1e6);
        token.fund(1000 * 1e6);
        assertEq(token.protocolCrowdfundFees(), 100 * 1e6, "Protocol fees should accumulate in variable");
        token.fund(4000 * 1e6);
        assertEq(token.protocolCrowdfundFees(), 0, "Protocol fees should be at 0");

        vm.stopPrank();

        vm.startPrank(owner);
        assertEq(IERC20(usdc).balanceOf(address(factory)), 500e6 + 99e6, "Protocol fees are not correct"); //includes $99 launchfee

        factory.withdraw();
        assertEq(IERC20(usdc).balanceOf(address(factory)), 0, "Protocol fees are were not withdrawn");

        vm.stopPrank();

        // assertEq(
        //     IERC20(usdc).balanceOf(owner),
        //     initialOwnerBalance + protocolFeesToBePaid,
        //     "Protocol fees were not withdrawn"
        // );
    }

    // function testFail_WithdrawProtocolFees_WrongPhase() public {
    //     vm.startPrank(bob);

    //     IERC20(usdc).approve(address(token), 100_000 * 1e6);
    //     token.fund(4000 * 1e6);
    //     vm.stopPrank();
    //     vm.startPrank(owner);
    //     token.withdrawProtocolFees();
    //     vm.stopPrank();
    // }

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
