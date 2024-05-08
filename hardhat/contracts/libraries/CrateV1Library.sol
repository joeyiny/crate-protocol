//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

library CrateV1Library {
    function quote(
        uint amountA,
        uint reserveA,
        uint reserveB
    ) internal pure returns (uint amountB) {
        require(amountA > 0, "CrateV1Library: INSUFFICIENT_AMOUNT");
        require(
            reserveA > 0 && reserveB > 0,
            "CrateV1Library: INSUFFICIENT_LIQUIDITY"
        );
        amountB = (amountA * (reserveB)) / reserveA;
    }

    function getAmountOut(
        uint amountIn,
        uint reserveIn,
        uint reserveOut
    ) internal pure returns (uint amountOut) {
        require(amountIn > 0, "CrateV1Library: INSUFFICIENT_INPUT_AMOUNT");
        require(
            reserveIn > 0 && reserveOut > 0,
            "CrateV1Library: INSUFFICIENT_LIQUIDITY"
        );
        uint amountInWithFee = amountIn * (997);
        uint numerator = amountInWithFee * (reserveOut);
        uint denominator = reserveIn * (1000) + (amountInWithFee);
        amountOut = numerator / denominator;
    }

    function getAmountIn(
        uint amountOut,
        uint reserveIn,
        uint reserveOut
    ) internal pure returns (uint amountIn) {
        require(amountOut > 0, "CrateV1Library: INSUFFICIENT_OUTPUT_AMOUNT");
        require(
            reserveIn > 0 && reserveOut > 0,
            "CrateV1Library: INSUFFICIENT_LIQUIDITY"
        );
        uint numerator = reserveIn * (amountOut) * (1000);
        uint denominator = reserveOut - (amountOut) * (997);
        amountIn = (numerator / denominator) + (1);
    }

    function getAmountsOut(
        address factory,
        uint amountIn,
        address[] memory path
    ) internal view returns (uint[] memory amounts) {
        require(path.length >= 2, "UniswapV2Library: INVALID_PATH");
        amounts = new uint[](path.length);
        amounts[0] = amountIn;
        for (uint i; i < path.length - 1; i++) {
            (uint reserveIn, uint reserveOut) = getReserves(
                factory,
                path[i],
                path[i + 1]
            );
            amounts[i + 1] = getAmountOut(amounts[i], reserveIn, reserveOut);
        }
    }
}
