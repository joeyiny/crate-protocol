// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

interface ICrateV2 {
    /// FACTORY ///

    event TokenLaunched(address tokenAddress, string name, string symbol);
    event LaunchCostUpdated(uint256 newCost);

    /// CRATE ///

    enum Phase {
        CROWDFUND,
        BONDING_CURVE,
        MARKET,
        CANCELED
    }

    event TokenTrade(address trader, uint256 tokenAmount, bool isPurchase, uint256 ethAmount);
    event Fund(address funder, uint256 usdcAmount, uint256 tokenAmount);
    event CrowdfundCompleted();
    event CrowdfundCanceled();
    event ClaimRefund(address user, uint256 usdcAmount);
    event BondingCurveEnded();
    event ArtistFeesWithdrawn(address artist, uint256 amount);
    event ProtocolFeesPaid(uint256 amount);
    event LiquidityAdded(uint256 amountToken, uint256 amountETH, uint256 liquidity);

    error Zero();
    error WrongPhase();
    error OnlyArtist();
    error TransferFailed();
    error InsufficientTokens();
    error MustBuyAtLeastOneToken();
    error MustSellAtLeastOneToken();
    error InsufficientPayment();
    error SlippageToleranceExceeded();
}
