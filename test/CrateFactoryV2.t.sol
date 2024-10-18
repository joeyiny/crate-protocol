// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TestUtils} from "test/utils/TestUtils.sol";
import {CrateFactoryV2} from "src/CrateFactoryV2.sol";
import {CrateTokenV2} from "src/CrateTokenV2.sol";
import {ICrateV2} from "src/interfaces/ICrateV2.sol";
import {MockUSDC} from "test/mock/MockUSDC.sol";

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

contract CrateFactoryV2Test is TestUtils, ICrateV2 {
    CrateFactoryV2 factory;
    address uniswapRouter = 0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24;
    address usdc;

    address tester;

    function setUp() public {
        // Set up the environment before each test
        usdc = address(new MockUSDC());
        deal(usdc, address(this), 1_000_000e6); // Give tester 1,000,000 USDC
        factory = new CrateFactoryV2(usdc);
    }

    function testCreateToken() public {
        // Send exactly the required ETH to create a token

        IERC20(usdc).approve(address(factory), factory.launchCost());

        string memory name = "TestToken";
        string memory symbol = "TTK";
        string memory songURI = "example.com";
        bytes32 salt = keccak256(abi.encode(name, symbol, songURI));
        address tokenAddress = address(factory.createToken(name, symbol, songURI, salt, 5000e6));

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
            IERC20(usdc).approve(address(factory), factory.launchCost());
            string memory name = string(abi.encodePacked("Token", i));
            string memory symbol = string(abi.encodePacked("SYM", i));
            string memory songURI = string(abi.encodePacked("example.com", i));
            bytes32 salt = keccak256(abi.encode(name, symbol, songURI));

            address tokenAddress = address(factory.createToken(name, symbol, songURI, salt, 5000e6));

            assertEq(factory.allTokens(i), tokenAddress, "Token address should be recorded in allTokens.");
        }
    }

    function testFailCreateTokenWithInsufficientUSDC() public {
        // Attempt to create a token without sending enough USDC should fail
        address alice = address(0x123);
        vm.deal(alice, 1 ether);
        deal(usdc, alice, 90 * 1e6);
        vm.startPrank(alice);

        IERC20(usdc).approve(address(factory), factory.launchCost());

        string memory name = "FailToken";
        string memory symbol = "FTK";
        string memory songURI = "example.com";
        bytes32 salt = keccak256(abi.encode(name, symbol, songURI));

        factory.createToken(name, symbol, songURI, salt, 5000e6); // Not enough USDC
        vm.stopPrank();
    }

    function testUpdateLaunchCostAndCreateToken() public {
        // First, update the launch cost by the owner
        uint256 newLaunchCost = 400e6;

        factory.updateLaunchCost(newLaunchCost);
        assertEq(factory.launchCost(), newLaunchCost, "Launch cost should be updated to new value.");
    }

    function testFailSameSalt() public {
        string memory name = "UniqueToken";
        string memory symbol = "UNQ";
        string memory songURI = "unique.com";
        bytes32 salt = keccak256(abi.encode(name, symbol, songURI));

        // First token creation should succeed
        address firstClone = address(factory.createToken(name, symbol, songURI, salt, 5000e6));
        assertTrue(firstClone != address(0), "First token creation failed");

        // Second token creation with the same salt should fail
        factory.createToken(name, symbol, songURI, salt, 5000e6);
    }

    receive() external payable {}
}
