//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {UQ112x112} from "./UQ112x112.sol";


contract BondingCurve {

    uint112 private reserveToken; // uses single storage slot, accessible via getReserves
    uint112 private reserveWETH; // uses single storage slot, accessible via getReserves
    uint32 private blockTimestampLast; // uses single storage slot, accessible via getReserves

    WETH address public weth;

    uint public priceTokenCumulativeLast;
    uint public priceWETHCumulativeLast;
    uint256 public tokensInCurve;

    constructor(WETH9 _weth) {
        weth = _weth;
        tokensInCurve = 80_000 * 1e18;
    }

    function swap(
        uint amountTokenOut,
        uint amountWETHOut,
        address to
    ) external ReentrancyGuard {
        require(
            amountTokenOut > 0 || amountWETHOut > 0,
            "Crate: INSUFFICIENT_OUTPUT_AMOUNT"
        );
        (uint112 _reserveToken, uint112 _reserveWETH, ) = getReserves(); // gas savings
        require(
            amountTokenOut < _reserveToken && amountWETHOut < _reserveWETH,
            "crate: INSUFFICIENT_LIQUIDITY"
        );

        uint balanceToken;
        uint balanceWETH;
        {
            // scope for _token{0,1}, avoids stack too deep errors
            require(to != address(this) && to != address(weth), "Crate: INVALID_TO");
            if (amountTokenOut > 0) _safeTransfer(address(this), to, amountTokenOut); // optimistically transfer tokens
            if (amountWETHOut > 0) _safeTransfer(address(weth), to, amountWETHOut); // optimistically transfer tokens
            balanceToken = tokensInCurve - amountTokenOut;
            balanceWETH = weth.balanceOf(address(this));
        }
        uint amountTokenIn = balanceToken > _reserveToken - amountTokenOut
            ? balanceToken - (_reserveToken - amountTokenOut)
            : 0;
        uint amountWETHIn = balanceWETH > _reserveWETH - amountWETHOut
            ? balance1 - (_reserveWETH - amountWETHOut)
            : 0;
        require(
            amountTokenIn > 0 || amountWETHIn > 0,
            "Create: INSUFFICIENT_INPUT_AMOUNT"
        );
        {
            // scope for reserve{0,1}Adjusted, avoids stack too deep errors
            uint balanceTokenAdjusted = balanceToken.mul(1000).sub(amountTokenIn.mul(3));
            uint balanceWETHAdjusted = balanceWETH.mul(1000).sub(amountWETHIn.mul(3));
            require(
                balanceTokenAdjusted.mul(balanceWETHAdjusted) >=
                    uint(_reserveToken).mul(_reserveWETH).mul(1000 ** 2),
                "Create: K"
            );
        }

        _update(balance0, balance1, _reserveToken, _reserveWETH);
        emit Swap(msg.sender, amountTokenIn, amountWETHIn, amountTokenOut, amountWETHOut, to);
    }

    function _update(
        uint balanceToken,
        uint balanceWETH,
        uint112 _reserveToken,
        uint112 _reserveWETH
    ) private {
        require(
            balanceToken <= uint112(-1) && balanceWETH <= uint112(-1),
            "Crate: OVERFLOW"
        );
        uint32 blockTimestamp = uint32(block.timestamp % 2 ** 32);
        uint32 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired
        if (timeElapsed > 0 && _reserve0 != 0 && _reserve1 != 0) {
            // * never overflows, and + overflow is desired
            priceTokenCumulativeLast +=
                uint(UQ112x112.encode(_reserveWETH).uqdiv(_reserveToken)) *
                timeElapsed;
            priceWETHCumulativeLast +=
                uint(UQ112x112.encode(_reserveToken).uqdiv(_reserveWETH)) *
                timeElapsed;
        }
        reserveToken = uint112(balanceToken);
        reserveWETH = uint112(balanceWETH);
        blockTimestampLast = blockTimestamp;
        emit Sync(reserveToken, reserveWETH);
    }

   function getReserves() public view returns (uint112 _reserveToken, uint112 _reserveWETH, uint32 _blockTimestampLast) {
        _reserveToken = reserveToken;
        _reserveWETH = reserveWETH;
        _blockTimestampLast = blockTimestampLast;
    }

    function getTokenInCurve() public view returns (uint256) {
        return tokensInCurve;
    } 
}