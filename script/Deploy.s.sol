// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// USDC on base 0x833589fcd6edb6e08f4c7c32d4f71b54bda02913
import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {TokenFactory} from "../src/TokenFactory.sol";

contract Deploy is Script {
    function run() public {
        address usdc;
        if (block.chainid == 84532) {
            usdc = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;
        } else if (block.chainid == 8453) {
            usdc = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
        } else if (block.chainid == 31337) {
            usdc = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913; //same as base mainnet, change if you want mock usdc
        } else {
            revert("unsupported chain");
        }
        vm.startBroadcast();
        TokenFactory tokenLauncher = new TokenFactory(usdc, 1e6);
        vm.stopBroadcast();
    }
}
