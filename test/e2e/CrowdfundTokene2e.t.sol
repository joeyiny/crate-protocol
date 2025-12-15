// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

import {TestUtils} from "test/utils/TestUtils.sol";
import {MockUSDC} from "test/mock/MockUSDC.sol";
import {TokenFactory} from "src/TokenFactory.sol";
import {CrowdfundToken} from "src/CrowdfundToken.sol";
import {ICrateV2} from "src/interfaces/ICrateV2.sol";

contract CrowdfundTokenTest is TestUtils, ICrateV2 {
    TokenFactory factory;
    CrowdfundToken token;

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
        factory = new TokenFactory(usdc,19e6);
        string memory name = "TestToken";
        string memory symbol = "TTK";
        string memory songURI = "example.com";
        bytes32 salt = keccak256(abi.encode(name, symbol, songURI));

        IERC20(usdc).approve(address(factory), factory.launchCost());
        address tokenAddress = address(factory.createToken(name, symbol, songURI, salt, 5000e6));
        token = CrowdfundToken(tokenAddress);
        vm.stopPrank();
    }

    function test_UpdateTokenImplementation() public {
        address newImplementation = address(new CrowdfundToken());

        // Non-owner should fail
        vm.startPrank(alice);
        vm.expectRevert();
        factory.updateTokenImplementation(newImplementation);
        vm.stopPrank();

        // Zero address should fail
        vm.startPrank(owner);
        vm.expectRevert("Invalid implementation");
        factory.updateTokenImplementation(address(0));

        // Non-contract address should fail
        vm.expectRevert("Not a contract");
        factory.updateTokenImplementation(address(0x123));

        // Valid implementation should succeed
        factory.updateTokenImplementation(newImplementation);

        // Verify new implementation works by creating a token
        string memory name = "NewImplToken";
        string memory symbol = "NIT";
        string memory songURI = "example.com/new";
        bytes32 salt = keccak256(abi.encode(name, symbol, songURI));
        IERC20(usdc).approve(address(factory), factory.launchCost());
        address tokenAddress = factory.createToken(name, symbol, songURI, salt, 5000e6);

        assertTrue(tokenAddress != address(0), "Token creation with new implementation failed");
        vm.stopPrank();
    }

    function test_CrateTokenAddress() public {
        // Test prediction before token exists
        string memory name = "PredictToken";
        string memory symbol = "PRED";
        string memory songURI = "example.com/predict";
        bytes32 salt = keccak256(abi.encode(name, symbol, songURI));

        (address predicted, bool exists) = factory.crateTokenAddress(bob, salt);
        assertFalse(exists, "Token should not exist yet");

        // Create token
        vm.startPrank(bob);
        IERC20(usdc).approve(address(factory), factory.launchCost());
        address actual = factory.createToken(name, symbol, songURI, salt, 5000e6);
        vm.stopPrank();

        // Verify prediction was correct
        assertEq(predicted, actual, "Predicted address should match actual");

        // Check exists flag after creation
        (address addr, bool shouldExist) = factory.crateTokenAddress(bob, salt);
        assertTrue(shouldExist, "Token should now exist");
        assertEq(addr, actual, "Address should match");
    }

    function test_InvalidCrowdfundGoals() public {
        vm.startPrank(owner);
        // Test too low
        vm.expectRevert(ICrateV2.InvalidCrowdfundGoal.selector);
        factory.createToken("Test", "TST", "uri", bytes32(0), 9e6);
        vm.expectRevert(ICrateV2.InvalidCrowdfundGoal.selector);
        factory.createToken("Test", "TST", "uri", bytes32(0), 1);
        vm.expectRevert(ICrateV2.InvalidCrowdfundGoal.selector);
        factory.createToken("Test", "TST", "uri", bytes32(0), 0);

        // Test too high
        vm.expectRevert(ICrateV2.InvalidCrowdfundGoal.selector);
        factory.createToken("Test", "TST", "uri", bytes32(0), 101000e6);

        vm.expectRevert("Invalid goal limits");
        factory.updateCrowdfundGoalLimits(1001e6, 1000e6);
    }

    function test_UpdateLaunchCost() public {
        uint256 newLaunchCost = 25e6; // $25

        deal(usdc, alice, 100_000 * 1e6);
        // Non-owner should fail
        vm.startPrank(alice);
        vm.expectRevert();
        factory.updateLaunchCost(newLaunchCost);
        vm.stopPrank();

        // Owner should succeed
        vm.startPrank(owner);
        factory.updateLaunchCost(newLaunchCost);
        vm.stopPrank();

        assertEq(factory.launchCost(), newLaunchCost, "Launch cost not updated correctly");

        // Verify new cost is required for token creation
        vm.startPrank(alice);
        string memory name = "TestToken";
        string memory symbol = "TTK";
        string memory songURI = "example.com";
        bytes32 salt = keccak256(abi.encode(name, symbol, songURI));

        // Should fail with old launch cost amount
        IERC20(usdc).approve(address(factory), 19e6);
        vm.expectRevert();
        factory.createToken(name, symbol, songURI, salt, 5000e6);

        // Should succeed with new launch cost amount
        IERC20(usdc).approve(address(factory), 25e6);
        factory.createToken(name, symbol, songURI, salt, 5000e6);
        vm.stopPrank();
    }

    function test_CannotTransferDuringCrowdfund() public {
        // Bob participates in the crowdfund
        vm.startPrank(bob);
        IERC20(usdc).approve(address(token), 100_000 * 1e6);
        token.fund(1000 * 1e6);

        // Verify Bob has received tokens
        uint256 bobTokenBalance = token.balanceOf(bob);
        assert(bobTokenBalance > 0);

        // Bob attempts to transfer tokens to Alice during the crowdfund phase
        vm.expectRevert("Transfers not allowed during crowdfund phase");
        token.transfer(alice, bobTokenBalance);

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
        CrowdfundToken validToken = CrowdfundToken(tokenAddress);
        vm.stopPrank();

        assertEq(validToken.crowdfundGoal(), validGoal);
    }

    function test_RevertWhen_CreateTokenWithBelowMinCrowdfundGoal() public {
        uint256 invalidGoal = 5e6;
        vm.startPrank(owner);
        string memory name = "BelowMinToken";
        string memory symbol = "BMT";
        string memory songURI = "example.com/belowmin";
        bytes32 salt = keccak256(abi.encode(name, symbol, songURI));
        vm.expectRevert(ICrateV2.InvalidCrowdfundGoal.selector);
        factory.createToken(name, symbol, songURI, salt, invalidGoal);
        vm.stopPrank();
    }

    function test_RevertWhen_CreateTokenWithAboveMaxCrowdfundGoal() public {
        uint256 invalidGoal = 200_000e6; // Above $100,000 maximum
        vm.startPrank(owner);
        string memory name = "AboveMaxToken";
        string memory symbol = "AMT";
        string memory songURI = "example.com/abovemax";
        bytes32 salt = keccak256(abi.encode(name, symbol, songURI));
        vm.expectRevert(ICrateV2.InvalidCrowdfundGoal.selector);
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
        CrowdfundToken newToken = CrowdfundToken(tokenAddress);
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
        vm.expectRevert("Can't withdraw in this phase.");
        token.withdrawArtistFees();

        vm.expectRevert("Not authorized.");
        token.completeCrowdfund();
        factory.approveTokenCrowdfund(address(token));
        token.withdrawArtistFees();

        uint256 finalArtistBalance = IERC20(usdc).balanceOf(owner);
        assertEq(finalArtistBalance, initialArtistBalance + 4500 * 1e6, "Artist did not receive the correct USDC");
        assertEq(token.artistCrowdfundFees(), 0, "Artist fees should be reset to zero");
        vm.stopPrank();
    }

    function test_RevertWhen_WithdrawArtistFees_WrongPhase() public {
        vm.startPrank(bob);

        IERC20(usdc).approve(address(token), 100_000 * 1e6);
        token.fund(4000 * 1e6);
        vm.stopPrank();
        vm.startPrank(owner);
        vm.expectRevert("Can't withdraw in this phase.");
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
        vm.stopPrank();

        assertTrue(token.phase() == Phase.PENDING, "Should be in pending phase.");

        vm.startPrank(owner);
        factory.approveTokenCrowdfund(address(token));
        assertEq(token.protocolCrowdfundFees(), 0, "Protocol fees should be at 0");

        vm.stopPrank();

        vm.startPrank(owner);
        assertEq(IERC20(usdc).balanceOf(address(factory)), 500e6 + 19e6, "Protocol fees are not correct"); //includes launchfee

        factory.withdraw();
        assertEq(IERC20(usdc).balanceOf(address(factory)), 0, "Protocol fees are were not withdrawn");

        vm.stopPrank();
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

    function test_RevertWhen_WithdrawArtistFees_WrongUser() public {
        vm.startPrank(bob);
        IERC20(usdc).approve(address(token), 100_000 * 1e6);
        token.fund(5000 * 1e6);
        vm.expectRevert();
        token.withdrawArtistFees();
        vm.stopPrank();
    }

    //Token shouldn't be created if the USDC transfer fails
    function test_UsdcTransferFail() public {
        MockUSDC(usdc).setFailTransfers(true);
        MockUSDC(usdc).approve(address(factory), factory.launchCost());
        vm.expectRevert();
        factory.createToken("Test", "TST", "uri", bytes32(0), 5000e6);
        MockUSDC(usdc).setFailTransfers(false);
    }

    //Token shouldn't be created if the USDC transfer fails
    function test_UsdcTransferFail_WithdrawProtocol_Fees() public {
        vm.startPrank(bob);

        IERC20(usdc).approve(address(token), 100_000 * 1e6);
        token.fund(5000 * 1e6);
        vm.stopPrank();

        vm.startPrank(owner);

        factory.approveTokenCrowdfund(address(token));
        MockUSDC(usdc).setFailTransfers(true);
        vm.expectRevert();
        factory.withdraw();
        MockUSDC(usdc).setFailTransfers(false);
    }
    // ---------- EXTRA TESTS FOR COVERAGE ---------- //

    function test_coverage_fund() public {
        vm.startPrank(bob);

        vm.expectRevert();
        token.fund(100e6);
        IERC20(usdc).approve(address(token), 100_000 * 1e6);
        vm.expectRevert();
        token.fund(0);
        MockUSDC(usdc).setFailTransfers(true);
        vm.expectRevert();
        token.fund(100e6);
        MockUSDC(usdc).setFailTransfers(false);
    }

    function test_coverage_completeCrowdfund() public {
        vm.startPrank(owner);
        vm.expectRevert("Incorrect phase");
        factory.approveTokenCrowdfund(address(token));
        vm.stopPrank();

        vm.startPrank(bob);

        IERC20(usdc).approve(address(token), 5_000 * 1e6);
        token.fund(5000e6);

        vm.expectRevert("Not authorized.");
        token.completeCrowdfund();

        vm.expectRevert();
        factory.approveTokenCrowdfund(address(token));

        IERC20(usdc).approve(address(factory), factory.launchCost());
        address newTokenAddress = factory.createToken("Test", "TST", "uri", bytes32(0), 5000e6);
        CrowdfundToken newToken = CrowdfundToken(newTokenAddress);

        IERC20(usdc).approve(address(newToken), 5_000 * 1e6);
        newToken.fund(5000e6);

        vm.expectRevert();
        factory.approveTokenCrowdfund(address(newToken));

        vm.expectRevert("Not authorized.");
        newToken.completeCrowdfund();

        vm.stopPrank();

        vm.startPrank(owner);

        vm.expectRevert("Not authorized.");
        token.completeCrowdfund();

        vm.expectRevert("Not authorized.");
        newToken.completeCrowdfund();

        factory.approveTokenCrowdfund(address(token));
        factory.approveTokenCrowdfund(address(newToken));
    }

    function test_coverage_cancelCrowdfund() public {
        CrowdfundToken bobsToken;
        vm.startPrank(bob);
        bytes32 salt2 = keccak256(abi.encode("a", "a", "a"));

        IERC20(usdc).approve(address(factory), factory.launchCost());
        address bobTA = address(factory.createToken("a", "a", "a", salt2, 5000e6));
        bobsToken = CrowdfundToken(bobTA);
        vm.stopPrank();

        vm.startPrank(alice);
        vm.expectRevert("Not authorized.");
        bobsToken.cancelCrowdfund();
        vm.stopPrank();

        vm.startPrank(bob);
        bobsToken.cancelCrowdfund();
        vm.stopPrank();
    }

    function test_coverage_claimRefund() public {
        vm.startPrank(bob);

        vm.expectRevert("Crowdfund not canceled");
        token.claimRefund();
        IERC20(usdc).approve(address(token), 100e6);
        token.fund(100e6);

        vm.startPrank(owner);
        factory.cancelTokenCrowdfund(address(token));
        vm.startPrank(bob);

        MockUSDC(usdc).setFailTransfers(true);
        vm.expectRevert("USDC refund failed");
        token.claimRefund();
        MockUSDC(usdc).setFailTransfers(false);

        token.claimRefund();

        vm.expectRevert("Refund already claimed");
        token.claimRefund();

        vm.startPrank(alice);
        vm.expectRevert("No funds to refund");
        token.claimRefund();
    }

    function test_coverage_withdrawArtistFees() public {
        vm.startPrank(bob);
        IERC20(usdc).approve(address(token), 5000e6);
        token.fund(5000e6);
        vm.startPrank(owner);
        factory.approveTokenCrowdfund(address(token));
        vm.startPrank(bob);
        vm.expectRevert(); //Only artist
        token.withdrawArtistFees();
    }
}
