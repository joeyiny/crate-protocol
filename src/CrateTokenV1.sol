//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../lib/multicaller/src/LibMulticaller.sol";
import {IUniswapV2Router02} from "../src/interfaces/IUniswapV2RouterV2.sol";

// The total supply is 100,000 tokens
// Once the bonding curve has sold out 80,000 tokens, the other 20,000 are put in Uniswap with the total ETH in the contract.
// The LP tokens are then burned, so no one can pull the liquidity.

contract CrateTokenV1 is ERC20Upgradeable, ReentrancyGuard {
    address public uniswapV2Router02;

    uint256 public constant SLIPPAGE_TOLERANCE = 250; // Slippage tolerance (500 basis points = 5%)

    uint256 private constant MAX_SUPPLY = 100_000 * 1e18;
    uint256 private constant MAX_CURVE_SUPPLY = 80_000 * 1e18;

    uint256 private constant CRATE_FEE_PERCENT = 25000000000000000;
    uint256 private constant ARTIST_FEE_PERCENT = 25000000000000000;

    bool public bondingCurveActive = true;

    address public protocolFeeDestination;
    address public artistFeeDestination;

    string public songURI;

    event TokenTrade(address trader, uint256 tokenAmount, bool isPurchase, uint256 ethAmount);

    event BondingCurveEnded();

    function initialize(
        address _uniswapV2Router02,
        string memory _name,
        string memory _symbol,
        address _protocolAddress,
        address _artistAddress,
        string memory _songURI
    ) public initializer {
        __ERC20_init(_name, _symbol);
        _mint(address(this), MAX_SUPPLY);
        artistFeeDestination = _artistAddress;
        protocolFeeDestination = _protocolAddress;
        uniswapV2Router02 = _uniswapV2Router02;
        bondingCurveActive = true;
        songURI = _songURI;
        _approve(address(this), uniswapV2Router02, MAX_SUPPLY);
    }

    function buyWithEth() external payable {
        // Take fees out of ETH, then see how many tokens you can buy with the remaining amount.
        uint256 cratePreFee = (msg.value * CRATE_FEE_PERCENT) / 1 ether;
        uint256 artistPreFee = (msg.value * ARTIST_FEE_PERCENT) / 1 ether;
        uint256 netValue = msg.value - cratePreFee - artistPreFee;
        uint256 tokensToBuy = estimateMaxPurchase(netValue);

        require(tokensToBuy > 0, "Not enough ETH provided to buy tokens.");

        //If you sent enough eth, then buy tokens.
        buy(tokensToBuy);
    }

    function buy(uint256 _amount) public payable nonReentrant {
        address sender = LibMulticaller.sender();

        require(bondingCurveActive, "Bonding curve ended");
        require(_amount <= tokensInCurve(), "Not enough tokens in the bonding curve.");
        if (tokensInCurve() >= 10 ** decimals()) {
            require(_amount >= 10 ** decimals(), "Cannot buy less than 1 token from the bonding curve.");
        } else {
            _amount = tokensInCurve();
        }

        uint256 price = getBuyPrice(_amount);
        uint256 crateFee = (price * CRATE_FEE_PERCENT) / 1 ether;
        uint256 artistFee = (price * ARTIST_FEE_PERCENT) / 1 ether;
        uint256 totalPayment = price + crateFee + artistFee;

        require(msg.value >= totalPayment, "Not enough Ether to complete purchase.");
        // Calculate the minimum amount of tokens that should be received based on the slippage tolerance
        uint256 minTokens = _amount - ((_amount * SLIPPAGE_TOLERANCE) / 10_000);

        require(balanceOf(address(this)) >= minTokens, "Slippage tolerance exceeded.");

        _transfer(address(this), sender, _amount);
        if (tokensInCurve() == 0) {
            bondingCurveActive = false;
            emit BondingCurveEnded();
        }
        emit TokenTrade(sender, _amount, true, totalPayment);

        (bool crateFeePaid,) = protocolFeeDestination.call{value: crateFee}("");
        require(crateFeePaid, "Failed to pay crate fee");

        (bool artistFeePaid,) = artistFeeDestination.call{value: artistFee}("");
        require(artistFeePaid, "Failed to pay artist fee");

        // Refund the remaining Ether to the buyer
        (bool refundSuccess,) = sender.call{value: msg.value - totalPayment}("");
        require(refundSuccess, "Refund failed");

        if (!bondingCurveActive) {
            _addLiquidity();
        }
    }

    function sell(uint256 _amount) external nonReentrant {
        address sender = LibMulticaller.sender();

        require(bondingCurveActive, "Bonding curve ended");
        require(balanceOf(sender) >= _amount, "Not enough tokens to sell");
        uint256 price = getSellPrice(_amount);
        uint256 crateFee = (price * CRATE_FEE_PERCENT) / 1 ether;
        uint256 artistFee = (price * ARTIST_FEE_PERCENT) / 1 ether;
        uint256 netSellerProceeds = price - crateFee - artistFee;

        // Calculate the minimum Ether that should be received based on the slippage tolerance
        uint256 minEther = netSellerProceeds - ((netSellerProceeds * SLIPPAGE_TOLERANCE) / 10_000);

        // Ensure the seller receives at least the minimum Ether after considering slippage
        require(address(this).balance >= minEther, "Slippage tolerance exceeded.");

        _transfer(sender, address(this), _amount);
        emit TokenTrade(sender, _amount, false, netSellerProceeds);

        (bool netProceedsSent,) = sender.call{value: netSellerProceeds}("");
        require(netProceedsSent, "Failed to send net seller proceeds");

        (bool crateFeePaid,) = protocolFeeDestination.call{value: crateFee}("");
        require(crateFeePaid, "Failed to pay crate fee");

        (bool artistFeePaid,) = artistFeeDestination.call{value: artistFee}("");
        require(artistFeePaid, "Failed to pay artist fee");
    }

    function estimateMaxPurchase(uint256 ethAmount) public view returns (uint256) {
        uint256 remainingSupply = tokensInCurve();
        uint256 lower = 0;
        uint256 upper = remainingSupply;
        while (lower < upper) {
            uint256 mid = (lower + upper + 1) / 2;
            if (getBuyPrice(mid) <= ethAmount) {
                lower = mid;
            } else {
                upper = mid - 1;
            }
        }
        return lower;
    }

    function getBuyPrice(uint256 amount) public view returns (uint256) {
        return getPrice(MAX_CURVE_SUPPLY - tokensInCurve(), amount);
    }

    function getSellPrice(uint256 amount) public view returns (uint256) {
        return getPrice(MAX_CURVE_SUPPLY - tokensInCurve() - amount, amount);
    }

    function getPrice(uint256 supply, uint256 amount) private pure returns (uint256) {
        return bondingCurve(supply + amount) - bondingCurve(supply);
    }

    // Takes in the amount of tokens, returns cost of all tokens up to that point.
    function bondingCurve(uint256 x) public pure returns (uint256) {
        return (x * (x + 1) * (2 * x + 1)) / 256000000000000000000000000000000000000000000000000;
        // Double check this math. The bonding curve should sell out at ~4.0000 ETH
    }

    function tokensInCurve() public view returns (uint256) {
        return balanceOf(address(this)) - (MAX_SUPPLY - MAX_CURVE_SUPPLY);
    }

    function _addLiquidity() internal {
        require(!bondingCurveActive, "The bonding curve is still active.");
        (uint256 amountToken, uint256 amountETH, uint256 liquidity) = IUniswapV2Router02(uniswapV2Router02)
            .addLiquidityETH{value: address(this).balance}(
            address(this),
            balanceOf(address(this)), // amountTokenDesired
            0, // amountTokenMin (set to 0 for simplicity)
            0, // amountETHMin (set to 0 for simplicity)
            address(0), //where to send LP tokens
            block.timestamp + 300 // Deadline (current time plus 300 seconds)
        );
        require(amountToken > 0 && amountETH > 0 && liquidity > 0, "Liquidity addition failed.");
    }
}
