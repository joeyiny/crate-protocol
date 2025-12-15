// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

interface ICrateV2 {
    /// FACTORY ///

    event TokenLaunched(address tokenAddress, string name, string symbol, uint256 usdcGoal);
    event LaunchCostUpdated(uint256 newCost);

    /// CRATE ///

    enum Phase {
        CROWDFUND,
        COMPLETED,
        CANCELED,
        PENDING //This is for when the admin needs to approve a group buy's completion before it can enter COMPLETED
    }

    struct BondingCurve {
        uint256 tokenAmount;
        uint256 usdcAmount;
        uint256 virtualUsdcAmount;
    }

    // event TokenTrade(address trader, uint256 tokenAmount, bool isPurchase, uint256 ethAmount);
    event Fund(address funder, uint256 usdcAmount, uint256 tokenAmount);
    event TokenPurchase(address buyer, uint256 usdcAmount, uint256 tokenAmount);
    event TokenSale(address seller, uint256 tokenAmount, uint256 usdcAmount);
    // event FinishCrowdfund();
    event StartBondingCurve(uint256 tokenReserve, uint256 realUsdcReserve, uint256 virtualUsdcReserve);
    // event CrowdfundCanceled();
    event ClaimRefund(address user, uint256 usdcAmount);
    event ArtistFeesWithdrawn(address artist, uint256 amount);
    event ProtocolFeesPaid(uint256 amount);
    event CrowdfundGoalUpdated(uint256 minimumGoal, uint256 maximumGoal);
    event EnterPhase(Phase phase);
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
