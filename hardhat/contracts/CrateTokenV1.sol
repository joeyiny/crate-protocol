//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IUniswapV2Router02} from "./interfaces/IUniswapV2Router02.sol";
import { BondingCurve } from "./libraries/BondingCurve.sol";

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";


// The total supply is 100,000 tokens
// Once the bonding curve has sold out 80,000 tokens, the other 20,000 are put in Uniswap with the total ETH in the contract.
// The LP tokens are then burned, so no one can pull the liquidity.

contract CrateTokenV1 is ERC20, ReentrancyGuard, BondingCurve {
    address public uniswapV2Router02;

    uint256 private constant MAX_SUPPLY = 100_000 * 1e18;

    uint256 private constant CRATE_FEE_PERCENT = 25000000000000000;
    uint256 private constant ARTIST_FEE_PERCENT = 25000000000000000;

    bool public bondingCurveActive = true;

    constructor() ERC20("Crate", "CRATE") BondingCurve("0xWETH") {}
    }

    event BondingCurveEnded();


    //override the update hook to dis allow transfers until bonding curve is over
    function _update(address from, address to, uint256 value)
        internal
        override(ERC20)
    {   
        //this is where we lock transfers until bonding curve is over
        // users still need to be able to transfer to and from this contract
        //may need to add something here
        if (from != address(this) || to != address(this)) {
            require(!bondingCurveActive, "The bonding curve is still active.");
        }
        super._update(from, to, value);
    }

    function swap(uint amountTokenOut, uint amountWETHOut, address to) 
        external 
        override(BondingCurve)
    {       
       //take fee before the swap is preformed
       //chek if the liquidity pool can be created
         //if it can be created, create it and return
            super.swap(amountTokenOut, amountWETHOut, to);
    }
    

    function _addLiquidity() internal {
        require(!bondingCurveActive, "The bonding curve is still active.");
        (uint amountToken, uint amountETH, uint liquidity) = IUniswapV2Router02(
            uniswapV2Router02
        ).addLiquidityETH{value: address(this).balance}(
            address(this),
            balanceOf(address(this)), // amountTokenDesired
            0, // amountTokenMin (set to 0 for simplicity)
            0, // amountETHMin (set to 0 for simplicity)
            address(0), //where to send LP tokens
            block.timestamp + 300 // Deadline (current time plus 300 seconds)
        );
        require(
            amountToken > 0 && amountETH > 0 && liquidity > 0,
            "Liquidity addition failed."
        );
    }
