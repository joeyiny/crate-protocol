//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../lib/multicaller/src/LibMulticaller.sol";
import {IUniswapV2Router02} from "../src/interfaces/IUniswapV2RouterV2.sol";

// The total supply is 117,000 tokens
// Once the bonding curve has sold out 80,000 tokens, the other 37,000 are put in Uniswap with the total ETH in the contract.
// The LP tokens are then burned, so no one can pull the liquidity.

contract CrateTokenV1 is ERC20Upgradeable, ReentrancyGuard {
    address public uniswapV2Router02;

    uint256 public constant SLIPPAGE_TOLERANCE = 250; // Slippage tolerance (500 basis points = 5%)

    uint256 private constant MAX_SUPPLY = 106_500 * 1e18;
    uint256 private constant MAX_CURVE_SUPPLY = 80_000 * 1e18;

    uint256 public tokensInCurve;

    uint256 private constant CRATE_FEE_PERCENT = 5000000000000000;
    uint256 private constant ARTIST_FEE_PERCENT = 5000000000000000;

    bool public bondingCurveActive = true;

    address public protocolFeeDestination;
    address public artistFeeDestination;

    string public songURI;

    uint256 public artistFees;

    event TokenTrade(address trader, uint256 tokenAmount, bool isPurchase, uint256 ethAmount);
    event BondingCurveEnded();
    event ArtistFeesWithdrawn(address artist, uint256 amount);
    event LiquidityAdded(uint256 amountToken, uint256 amountETH, uint256 liquidity);

    constructor() {
        _disableInitializers();
    }

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

        tokensInCurve = MAX_CURVE_SUPPLY;
        songURI = _songURI;
        _approve(address(this), uniswapV2Router02, MAX_SUPPLY);
    }

    function buyWithEth(uint256 minTokensReceivable) external payable {
        // Take fees out of ETH, then see how many tokens you can buy with the remaining amount.
        require(bondingCurveActive, "Bonding curve ended");
        require(tokensInCurve > 0, "Bonding curve is sold out");

        uint256 preFee =
            (msg.value * (CRATE_FEE_PERCENT + ARTIST_FEE_PERCENT)) / (CRATE_FEE_PERCENT + ARTIST_FEE_PERCENT + 1 ether);
        uint256 netValue = msg.value - preFee;
        uint256 tokensToBuy = estimateMaxPurchase(netValue);

        require(tokensToBuy > 0, "Not enough ETH provided to buy tokens.");
        require(tokensToBuy >= minTokensReceivable, "Slippage tolerance exceeded.");

        //If you sent enough eth, then buy tokens.
        buy(tokensToBuy);
    }

    function buy(uint256 _amount) public payable nonReentrant {
        address sender = LibMulticaller.sender();

        require(bondingCurveActive, "Bonding curve ended");
        require(_amount <= tokensInCurve, "Not enough tokens in the bonding curve.");
        if (tokensInCurve >= 10 ** decimals()) {
            require(_amount >= 10 ** decimals(), "Cannot buy less than 1 token from the bonding curve.");
        } else {
            _amount = tokensInCurve;
        }

        uint256 price = getBuyPrice(_amount);
        uint256 crateFee = (price * CRATE_FEE_PERCENT) / 1 ether;
        uint256 artistFee = (price * ARTIST_FEE_PERCENT) / 1 ether;
        uint256 totalPayment = price + crateFee + artistFee;
        artistFees += artistFee;

        require(msg.value >= totalPayment, "Not enough Ether to complete purchase.");
        // Calculate the minimum amount of tokens that should be received based on the slippage tolerance
        uint256 minTokens = _amount - ((_amount * SLIPPAGE_TOLERANCE) / 10_000);

        require(balanceOf(address(this)) >= minTokens, "Slippage tolerance exceeded.");

        tokensInCurve -= _amount;
        _transfer(address(this), sender, _amount);

        if (tokensInCurve == 0) {
            bondingCurveActive = false;
            emit BondingCurveEnded();
        }
        emit TokenTrade(sender, _amount, true, totalPayment);

        (bool crateFeePaid,) = protocolFeeDestination.call{value: crateFee}("");
        require(crateFeePaid, "Failed to pay crate fee");

        // Refund the remaining Ether to the buyer
        (bool refundSuccess,) = sender.call{value: msg.value - totalPayment}("");
        require(refundSuccess, "Refund failed");

        if (!bondingCurveActive) {
            _addLiquidity();
        }
    }

    function sell(uint256 _amount, uint256 minEtherReceivable) external nonReentrant {
        address sender = LibMulticaller.sender();

        require(bondingCurveActive, "Bonding curve ended");
        require(balanceOf(sender) >= _amount, "Not enough tokens to sell");
        require(_amount >= 10 ** decimals(), "Selling less than 10 tokens from the bonding curve is not permitted.");
        uint256 price = getSellPrice(_amount);
        uint256 crateFee = (price * CRATE_FEE_PERCENT) / 1 ether;
        uint256 artistFee = (price * ARTIST_FEE_PERCENT) / 1 ether;
        uint256 netSellerProceeds = price - crateFee - artistFee;
        artistFees += artistFee;

        require(netSellerProceeds >= minEtherReceivable, "Slippage tolerance exceeded.");

        tokensInCurve += _amount;
        _transfer(sender, address(this), _amount);

        emit TokenTrade(sender, _amount, false, netSellerProceeds);

        (bool netProceedsSent,) = sender.call{value: netSellerProceeds}("");
        require(netProceedsSent, "Failed to send net seller proceeds");

        (bool crateFeePaid,) = protocolFeeDestination.call{value: crateFee}("");
        require(crateFeePaid, "Failed to pay crate fee");
    }

    function estimateMaxPurchase(uint256 ethAmount) public view returns (uint256) {
        uint256 remainingSupply = tokensInCurve;
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
        return getPrice(MAX_CURVE_SUPPLY - tokensInCurve, amount);
    }

    function getSellPrice(uint256 amount) public view returns (uint256) {
        return getPrice(MAX_CURVE_SUPPLY - tokensInCurve - amount, amount);
    }

    function getPrice(uint256 supply, uint256 amount) private pure returns (uint256) {
        return bondingCurve(supply + amount) - bondingCurve(supply);
    }

    // Takes in the amount of tokens, returns cost of all tokens up to that point.
    function bondingCurve(uint256 x) public pure returns (uint256) {
        return (x * (x / 1e10 + 1)) / 16e16;
    }

    function _addLiquidity() internal {
        require(!bondingCurveActive, "The bonding curve is still active.");
        uint256 amountTokenDesired = balanceOf(address(this));
        uint256 amountETHDesired = address(this).balance - artistFees - 0.3 ether;

        // Ensure we have some tokens and ETH to add to the pool
        require(amountTokenDesired > 0 && amountETHDesired > 0, "Insufficient tokens or ETH for liquidity.");

        // Calculate the minimum amounts based on a fair price to prevent front-running
        uint256 minTokenPrice = getPrice(MAX_CURVE_SUPPLY, 1e18); // Fair market price for 1 token
        uint256 minTokens = (amountETHDesired * 1e18) / minTokenPrice; // Minimum tokens based on fair price

        (uint256 amountToken, uint256 amountETH, uint256 liquidity) = IUniswapV2Router02(uniswapV2Router02)
            .addLiquidityETH{value: address(this).balance - artistFees - 0.3 ether}(
            address(this),
            amountTokenDesired, // amountTokenDesired
            minTokens, // amountTokenMin
            amountETHDesired, // amountETHMin
            address(0), //where to send LP tokens
            block.timestamp + 300 // Deadline (current time plus 300 seconds)
        );
        require(amountToken > 0 && amountETH > 0 && liquidity > 0, "Liquidity addition failed.");
        (bool protocolFeePaid,) = protocolFeeDestination.call{value: 0.3 ether}("");
        require(protocolFeePaid, "Failed to pay protocol fee");

        emit LiquidityAdded(amountToken, amountETH, liquidity);
    }

    function _update(address from, address to, uint256 value) internal override {
        // only allow transfers to/fro token contract during bonding curve phase
        if (from != address(this) && to != address(this)) {
            require(!bondingCurveActive, "bonding curve active");
        }
        super._update(from, to, value);
    }

    function withdrawArtistFees() public {
        address sender = LibMulticaller.sender();
        require(sender == artistFeeDestination, "Unauthorized");
        require(artistFees > 0, "No fees to withdraw");
        uint256 fees = artistFees;
        artistFees = 0;
        (bool artistFeePaid,) = artistFeeDestination.call{value: fees, gas: 2300}("");
        require(artistFeePaid, "Failed to pay artist fee");
        emit ArtistFeesWithdrawn(artistFeeDestination, fees);
    }
}
