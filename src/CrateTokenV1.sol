//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {ERC20Upgradeable} from "@openzeppelin-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {LibMulticaller} from "@multicaller/LibMulticaller.sol";
import {IUniswapV2Router02} from "src/interfaces/IUniswapV2RouterV2.sol";
import {ICrateV1} from "src/interfaces/ICrateV1.sol";

// The total supply is 117,000 tokens
// Once the bonding curve has sold out 80,000 tokens, the other 37,000 are put in Uniswap with the total ETH in the contract.
// The LP tokens are then burned, so no one can pull the liquidity.
contract CrateTokenV1 is ERC20Upgradeable, ReentrancyGuard, ICrateV1 {
    uint256 private constant MAX_SUPPLY = 117_000e18;
    uint256 private constant MAX_CURVE_SUPPLY = 80_000e18;
    uint256 private constant CROWDFUND_THRESHOLD = 60_000e18;
    uint256 private constant CRATE_FEE_PERCENT = 5e15;
    uint256 private constant ARTIST_FEE_PERCENT = 5e15;

    address public uniswapV2Router02;
    address public protocolFeeDestination;
    address public artistFeeDestination;

    uint256 public tokensInCurve;
    uint256 public artistFees;

    mapping(address => uint256) public crowdfund;

    string public songURI;

    Phase public phase;

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
        phase = Phase.CROWDFUND;
        tokensInCurve = MAX_CURVE_SUPPLY;
        songURI = _songURI;
        _approve(address(this), uniswapV2Router02, MAX_SUPPLY);
    }

    /// PUBLIC ///

    function buyWithEth(uint256 minTokensReceivable) external payable {
        uint256 preFee =
            (msg.value * (CRATE_FEE_PERCENT + ARTIST_FEE_PERCENT)) / (CRATE_FEE_PERCENT + ARTIST_FEE_PERCENT + 1 ether);
        uint256 netValue = ((msg.value - preFee) * 999) / 1000;
        uint256 tokensToBuy = estimateMaxPurchase(netValue);
        if (tokensToBuy == 0) revert Zero();
        if (tokensToBuy < minTokensReceivable) revert SlippageToleranceExceeded();
        buy(tokensToBuy);
    }

    function buy(uint256 _amount) public payable nonReentrant {
        if (_amount > tokensInCurve) revert InsufficientTokens();
        if (tokensInCurve >= 10 ** decimals()) {
            if (_amount < 10 ** decimals()) revert MustBuyAtLeastOneToken();
        } else {
            _amount = tokensInCurve;
        }

        address sender = LibMulticaller.sender();
        uint256 totalPayment;
        uint256 crateFee;
        uint256 artistFee;

        if (phase == Phase.CROWDFUND) {
            if (tokensInCurve - _amount < CROWDFUND_THRESHOLD) {
                phase = Phase.BONDING_CURVE;
                uint256 excess = CROWDFUND_THRESHOLD - (tokensInCurve - _amount);
                uint256 crowdfundAmount = _amount - excess;
                uint256 crowdfundPrice = getBuyPrice(crowdfundAmount);
                tokensInCurve -= crowdfundAmount;
                crowdfund[sender] += crowdfundAmount;
                uint256 bondingCurvePrice = getBuyPrice(excess);
                tokensInCurve -= excess;
                crateFee = (crowdfundPrice / 10) + (bondingCurvePrice * CRATE_FEE_PERCENT) / 1 ether;
                artistFee = ((crowdfundPrice * 9) / 10) + (bondingCurvePrice * ARTIST_FEE_PERCENT) / 1 ether;
                totalPayment = crateFee + artistFee + bondingCurvePrice;
            } else {
                uint256 price = getBuyPrice(_amount);
                tokensInCurve -= _amount;
                crowdfund[sender] += _amount;
                crateFee = (price / 10);
                artistFee = ((price * 9) / 10);
                totalPayment = crateFee + artistFee;
            }
        } else if (phase == Phase.BONDING_CURVE) {
            uint256 price = getBuyPrice(_amount);
            tokensInCurve -= _amount;
            crateFee = (price * CRATE_FEE_PERCENT) / 1 ether;
            artistFee = (price * ARTIST_FEE_PERCENT) / 1 ether;
            totalPayment = price + crateFee + artistFee;
        } else {
            revert WrongPhase();
        }

        artistFees += artistFee;
        if (msg.value < totalPayment) revert InsufficientPayment();

        _transfer(address(this), sender, _amount);
        emit TokenTrade(sender, _amount, true, totalPayment);

        (bool refundSuccess,) = (sender).call{value: msg.value - totalPayment}("");
        if (!refundSuccess) revert TransferFailed();

        (bool crateFeePaid,) = protocolFeeDestination.call{value: crateFee}("");
        if (!crateFeePaid) revert TransferFailed();

        if (tokensInCurve == 0) {
            phase = Phase.MARKET;
            _addLiquidity();
            emit BondingCurveEnded();
        }
    }

    function sell(uint256 _amount, uint256 minEtherReceivable) external nonReentrant {
        address sender = LibMulticaller.sender();

        if (phase != Phase.BONDING_CURVE) revert WrongPhase();
        if (balanceOf(sender) < _amount + crowdfund[sender]) revert InsufficientTokens();
        if (_amount < 10 ** decimals()) revert MustSellAtLeastOneToken();

        uint256 price = getSellPrice(_amount);
        uint256 crateFee = (price * CRATE_FEE_PERCENT) / 1 ether;
        uint256 artistFee = (price * ARTIST_FEE_PERCENT) / 1 ether;
        artistFees += artistFee;
        uint256 netSellerProceeds = price - crateFee - artistFee;
        if (netSellerProceeds < minEtherReceivable) revert SlippageToleranceExceeded();

        tokensInCurve += _amount;
        _transfer(sender, address(this), _amount);
        emit TokenTrade(sender, _amount, false, netSellerProceeds);

        (bool netProceedsSent,) = (sender).call{value: netSellerProceeds}("");
        if (!netProceedsSent) revert TransferFailed();

        (bool crateFeePaid,) = protocolFeeDestination.call{value: crateFee}("");
        if (!crateFeePaid) revert TransferFailed();
    }

    function withdrawArtistFees() public nonReentrant {
        address sender = LibMulticaller.sender();
        if (sender != artistFeeDestination) revert OnlyArtist();
        if (artistFees == 0) revert Zero();
        uint256 fees = artistFees;
        artistFees = 0;
        (bool artistFeePaid,) = artistFeeDestination.call{value: fees}("");
        if (!artistFeePaid) revert TransferFailed();
        emit ArtistFeesWithdrawn(artistFeeDestination, fees);
    }

    /// VIEW ///

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

    function bondingCurve(uint256 x) public pure returns (uint256) {
        return (x * (x / 1e10 + 1)) / 16e16;
    }

    /// INTERNAL ///

    function _addLiquidity() internal {
        uint256 amountTokenDesired = balanceOf(address(this));
        uint256 amountETHDesired = address(this).balance - artistFees - 0.3 ether;
        if (amountTokenDesired == 0 || amountETHDesired == 0) revert Zero();

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
            block.timestamp // Deadline (current time)
        );
        if (amountToken == 0 || amountETH == 0 || liquidity == 0) revert Zero();
        (bool protocolFeePaid,) = protocolFeeDestination.call{value: 0.3 ether}("");
        if (!protocolFeePaid) revert TransferFailed();
        emit LiquidityAdded(amountToken, amountETH, liquidity);
    }

    function _update(address from, address to, uint256 value) internal override {
        // only allow general transfers in market phase
        if (from != address(this) && to != address(this) && (phase != Phase.MARKET)) revert WrongPhase();
        super._update(from, to, value);
    }
}
