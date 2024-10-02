// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {CrateFactoryV2} from "src/CrateFactoryV2.sol";
import {CrateTokenV2} from "src/CrateTokenV2.sol";
import {IUniswapV2Router02} from "src/interfaces/IUniswapV2RouterV2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract TestUtils is Test {
    CrateFactoryV2 public factory;
    CrateTokenV2 public token;
    IERC20 public usdc;
    IUniswapV2Router02 public uniswapRouter;

    address owner = makeAddr("owner");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function setUp() public virtual {
        vm.deal(owner, 1000 ether);
        vm.deal(alice, 1000 ether);
        vm.deal(bob, 1000 ether);
    }

    modifier prank(address _user) {
        vm.startPrank(_user);
        _;
        vm.stopPrank();
    }

    function forkBase() public {
        uint256 baseFork = vm.createFork("https://1rpc.io/base");
        vm.selectFork(baseFork);

        usdc = IERC20(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913);
        uniswapRouter = IUniswapV2Router02(0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24);

        deal(address(usdc), owner, 1_000_000_000e6);
        deal(address(usdc), alice, 1_000_000_000e6);
        deal(address(usdc), bob, 1_000_000_000e6);
    }
}
