// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

interface ICrateV2 {
    /// FACTORY ///

    event TokenLaunched(address tokenAddress, string name, string symbol, uint256 usdcGoal);
    event LaunchCostUpdated(uint256 newCost);

    /// CRATE ///

    enum Phase {
        CROWDFUND,
        BONDING_CURVE,
        MARKET,
        CANCELED
    }

    // event TokenTrade(address trader, uint256 tokenAmount, bool isPurchase, uint256 ethAmount);
    event Fund(address funder, uint256 usdcAmount, uint256 tokenAmount);
    event TokenPurchase(address buyer, uint256 usdcAmount, uint256 tokenAmount);
    event TokenSale(address seller, uint256 tokenAmount, uint256 usdcAmount);
    event CrowdfundCompleted();
    event CrowdfundCanceled();
    event ClaimRefund(address user, uint256 usdcAmount);
    // event BondingCurveEnded();
    event ArtistFeesWithdrawn(address artist, uint256 amount);
    event ProtocolFeesPaid(uint256 amount);
    // event LiquidityAdded(uint256 amountToken, uint256 amountETH, uint256 liquidity);
    event CrowdfundGoalUpdated(uint256 minimumGoal, uint256 maximumGoal);

    error Zero();
    error WrongPhase();
    error OnlyArtist();
    error TransferFailed();
    error InsufficientTokens();
    error MustBuyAtLeastOneToken();
    error MustSellAtLeastOneToken();
    error InsufficientPayment();
    error SlippageToleranceExceeded();
    error InvalidCrowdfundGoal();
}
