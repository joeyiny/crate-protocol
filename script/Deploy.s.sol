// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// USDC on base 0x833589fcd6edb6e08f4c7c32d4f71b54bda02913
import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {TokenFactory} from "../src/TokenFactory.sol";

contract DeployStoa is Script {
    function run() public {
        vm.startBroadcast();
        TokenFactory tokenLauncher = new TokenFactory(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913,1e6); //usdc on base address
        //1e6 is the launch cost ($1 usdc)
        vm.stopBroadcast();
    }
}
