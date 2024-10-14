// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TestUtils} from "test/utils/TestUtils.sol";
import {CrateFactoryV2} from "src/CrateFactoryV2.sol";
import {CrateTokenV2} from "src/CrateTokenV2.sol";
import {ICrateV2} from "src/interfaces/ICrateV2.sol";

contract CrateFactoryV2Test is TestUtils, ICrateV2 {
    CrateFactoryV2 factory;
    address uniswapRouter = 0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24;
    address base = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913; //USDC on Base

    address tester;

    function setUp() public {
        // Set up the environment before each test
        tester = address(this);
        factory = new CrateFactoryV2(uniswapRouter, base);
    }

    function testCreateToken() public {
        // Send exactly the required ETH to create a token
        string memory name = "TestToken";
        string memory symbol = "TTK";
        string memory songURI = "example.com";
        bytes32 salt = keccak256(abi.encode(name, symbol, songURI));
        address tokenAddress = address(factory.createToken{value: 0.04 ether}(name, symbol, songURI, salt));

        // Check if the token was created and if the event was emitted
        assertTrue(tokenAddress != address(0), "Token creation failed.");
        assertEq(factory.allTokens(0), tokenAddress, "Token address should be recorded in allTokens.");

        // Check token details (assuming public view functions in CrateTokenV2 for this)
        CrateTokenV2 token = CrateTokenV2(tokenAddress);
        assertEq(token.name(), name, "Token name should match.");
        assertEq(token.symbol(), symbol, "Token symbol should match.");
        assertEq(token.songURI(), songURI, "Song URI should match.");
    }

    function testCreateMultipleTokens() public {
        // Test creating multiple tokens and ensure all are recorded correctly
        uint256 numTokens = 5;
        for (uint256 i = 0; i < numTokens; i++) {
            string memory name = string(abi.encodePacked("Token", i));
            string memory symbol = string(abi.encodePacked("SYM", i));
            string memory songURI = string(abi.encodePacked("example.com", i));

            bytes32 salt = keccak256(abi.encode(name, symbol, songURI));
            address tokenAddress = address(factory.createToken{value: 0.04 ether}(name, symbol, songURI, salt));
            assertEq(factory.allTokens(i), tokenAddress, "Token address should be recorded in allTokens.");
        }
    }

    function testFailCreateTokenWithInsufficientEth() public {
        // Attempt to create a token without sending enough ETH should fail
        string memory name = "FailToken";
        string memory symbol = "FTK";
        string memory songURI = "example.com";
        bytes32 salt = keccak256(abi.encode(name, symbol, songURI));

        factory.createToken{value: 0.0001 ether}(name, symbol, songURI, salt); // Not enough ETH
    }

    function testUpdateLaunchCostAndCreateToken() public {
        // First, update the launch cost by the owner
        uint256 newLaunchCost = 0.5 ether; // Updated launch cost
        factory.updateLaunchCost(newLaunchCost);
        assertEq(factory.launchCost(), newLaunchCost, "Launch cost should be updated to new value.");

        // Initial balance of the tester
        uint256 initialBalance = address(this).balance;

        //uint256 sentAmount = factory.launchCost();

        // Creating a token and sending more ETH than required
        string memory name = "ExcessToken";
        string memory symbol = "EXT";
        string memory songURI = "example.com";
        bytes32 salt = keccak256(abi.encode(name, symbol, songURI));

        address tokenAddress = address(factory.createToken{value: 0.5 ether}(name, symbol, songURI, salt));

        // Ensure the token is created
        assertTrue(tokenAddress != address(0), "Token creation failed.");

        // Ensure the excess ETH is refunded
        uint256 finalBalance = address(this).balance;
        uint256 expectedFinalBalance = initialBalance - factory.launchCost();
        assertEq(finalBalance, expectedFinalBalance, "Excess ETH was not refunded correctly.");
    }

    function testFailSameSalt() public {
        string memory name = "UniqueToken";
        string memory symbol = "UNQ";
        string memory songURI = "unique.com";
        bytes32 salt = keccak256(abi.encode(name, symbol, songURI));

        // First token creation should succeed
        address firstClone = address(factory.createToken{value: factory.launchCost()}(name, symbol, songURI, salt));
        assertTrue(firstClone != address(0), "First token creation failed");

        // Second token creation with the same salt should fail
        factory.createToken{value: factory.launchCost()}(name, symbol, songURI, salt);
    }

    receive() external payable {}
}
