// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IUniswapV2Router02} from "src/interfaces/IUniswapV2RouterV2.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockUSDC is ERC20 {
    constructor() ERC20("USDC", "USDC") {}

    function mint(address _to, uint256 _amount) external {
        _mint(_to, _amount);
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }
}

contract MockUniswapV2Router is IUniswapV2Router02 {
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external pure returns (uint amountA, uint amountB, uint liquidity) {
        tokenA;
        tokenB;
        amountADesired;
        amountBDesired;
        amountAMin;
        amountBMin;
        to;
        deadline;

        amountA;
        amountB;
        liquidity;
    }
}