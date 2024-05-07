// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Vm.sol";
import "ds-test/test.sol";
import "../src/CrateFactoryV1.sol";

contract CrateFactoryV1Test is DSTest {
    CrateFactoryV1 factory;
    address uniswapRouter = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address tester;

    function setUp() public {
        // Set up the environment before each test
        tester = address(this);
        factory = new CrateFactoryV1(uniswapRouter);
    }

    function testCreateToken() public {
        // Send exactly the required ETH to create a token
        string memory name = "TestToken";
        string memory symbol = "TTK";
        address tokenAddress = address(
            factory.createToken{value: 0.00125 ether}(name, symbol)
        );

        // Check if the token was created and if the event was emitted
        assertTrue(tokenAddress != address(0), "Token creation failed.");
        assertEq(
            factory.allTokens(0),
            tokenAddress,
            "Token address should be recorded in allTokens."
        );

        // Check token details (assuming public view functions in CrateTokenV1 for this)
        CrateTokenV1 token = CrateTokenV1(tokenAddress);
        assertEq(token.name(), name, "Token name should match.");
        assertEq(token.symbol(), symbol, "Token symbol should match.");
    }

    function testCreateMultipleTokens() public {
        // Test creating multiple tokens and ensure all are recorded correctly
        uint256 numTokens = 5;
        for (uint256 i = 0; i < numTokens; i++) {
            string memory name = string(abi.encodePacked("Token", i));
            string memory symbol = string(abi.encodePacked("SYM", i));
            address tokenAddress = address(
                factory.createToken{value: 0.00125 ether}(name, symbol)
            );
            assertEq(
                factory.allTokens(i),
                tokenAddress,
                "Token address should be recorded in allTokens."
            );
        }
    }

    function testFailCreateTokenWithInsufficientEth() public {
        // Attempt to create a token without sending enough ETH should fail
        string memory name = "FailToken";
        string memory symbol = "FTK";
        factory.createToken{value: 0.0001 ether}(name, symbol); // Not enough ETH
    }

    function testCreateTokenWithRefund() public {
        // Initial balance of the tester
        uint256 initialBalance = address(this).balance;

        // Excess amount over the launch cost
        uint256 sentAmount = 1 ether;

        // Creating a token and sending more ETH than required
        string memory name = "ExcessToken";
        string memory symbol = "EXT";
        address tokenAddress = address(
            factory.createToken{value: sentAmount}(name, symbol)
        );

        // Ensure the token is created
        assertTrue(tokenAddress != address(0), "Token creation failed.");

        // Ensure the excess ETH is refunded
        uint256 finalBalance = address(this).balance;
        uint256 expectedFinalBalance = initialBalance - factory.launchCost();
        assertEq(
            finalBalance,
            expectedFinalBalance,
            "Excess ETH was not refunded correctly."
        );

        // Optionally, check the event and token details
        CrateTokenV1 token = CrateTokenV1(tokenAddress);
        assertEq(token.name(), name, "Token name should match.");
        assertEq(token.symbol(), symbol, "Token symbol should match.");
    }

    function testUpdateLaunchCostAndCreateToken() public {
        // First, update the launch cost by the owner
        uint256 newLaunchCost = 0.001 ether; // Updated launch cost
        factory.updateLaunchCost(newLaunchCost);
        assertEq(
            factory.launchCost(),
            newLaunchCost,
            "Launch cost should be updated to new value."
        );

        // Initial balance of the tester
        uint256 initialBalance = address(this).balance;

        // Excess amount over the launch cost
        uint256 excessAmount = 0.002 ether; // 0.0005 ether is the launch cost
        uint256 sentAmount = factory.launchCost() + excessAmount;

        // Creating a token and sending more ETH than required
        string memory name = "ExcessToken";
        string memory symbol = "EXT";
        address tokenAddress = address(
            factory.createToken{value: sentAmount}(name, symbol)
        );

        // Ensure the token is created
        assertTrue(tokenAddress != address(0), "Token creation failed.");

        // Ensure the excess ETH is refunded
        uint256 finalBalance = address(this).balance;
        uint256 expectedFinalBalance = initialBalance - factory.launchCost();
        assertEq(
            finalBalance,
            expectedFinalBalance,
            "Excess ETH was not refunded correctly."
        );
    }

    receive() external payable {} // Allow this contract to receive ETH
}
