// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {ERC20Upgradeable} from "@openzeppelin-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {LibMulticaller} from "@multicaller/LibMulticaller.sol";
import {IUniswapV2Router02} from "src/interfaces/IUniswapV2RouterV2.sol";
import {ICrateV2} from "src/interfaces/ICrateV2.sol";

// The total supply is 117,000 tokens
// Once the bonding curve has sold out 80,000 tokens, the other 37,000 are put in Uniswap with the total USDC in the contract.
// The LP tokens are then burned, so no one can pull the liquidity.

contract CrateTokenV2 is ERC20Upgradeable, ReentrancyGuard, ICrateV2 {
    using SafeERC20 for IERC20;

    uint256 private constant MAX_SUPPLY = 117_000e18;
    uint256 private constant MAX_CURVE_SUPPLY = 80_000e18;
    uint256 private constant CROWDFUND_THRESHOLD = 60_000e18;

    uint256 private constant PERCENTAGE_SCALE = 1e6; // Scaling factor for 6 decimals
    uint256 private constant CRATE_FEE_PERCENT = 5000; // 0.5% represented with 6 decimals
    uint256 private constant ARTIST_FEE_PERCENT = 5000; // 0.5% represented with 6 decimals

    address public uniswapV2Router02;
    address public protocolFeeDestination;
    address public artistFeeDestination;

    IERC20 public usdcToken; // USDC Token

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
        address _usdcTokenAddress,
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
        usdcToken = IERC20(_usdcTokenAddress);
        phase = Phase.CROWDFUND;
        tokensInCurve = MAX_CURVE_SUPPLY;
        songURI = _songURI;
        _approve(address(this), uniswapV2Router02, MAX_SUPPLY);
        usdcToken.approve(uniswapV2Router02, type(uint256).max);
    }

    /// PUBLIC ///

    function buy(uint256 _amount) public nonReentrant {
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
                emit CrowdfundEnded();
                uint256 excess = CROWDFUND_THRESHOLD -
                    (tokensInCurve - _amount);
                uint256 crowdfundAmount = _amount - excess;
                uint256 crowdfundPrice = getBuyPrice(crowdfundAmount);
                tokensInCurve -= crowdfundAmount;
                crowdfund[sender] += crowdfundAmount;
                uint256 bondingCurvePrice = getBuyPrice(excess);
                tokensInCurve -= excess;
                crateFee =
                    (crowdfundPrice * CRATE_FEE_PERCENT) /
                    PERCENTAGE_SCALE +
                    (bondingCurvePrice * CRATE_FEE_PERCENT) /
                    PERCENTAGE_SCALE;
                artistFee =
                    (crowdfundPrice * (PERCENTAGE_SCALE - CRATE_FEE_PERCENT)) /
                    PERCENTAGE_SCALE +
                    (bondingCurvePrice * ARTIST_FEE_PERCENT) /
                    PERCENTAGE_SCALE;
                totalPayment = crateFee + artistFee + bondingCurvePrice;
            } else {
                uint256 price = getBuyPrice(_amount);
                tokensInCurve -= _amount;
                crowdfund[sender] += _amount;
                crateFee = (price * CRATE_FEE_PERCENT) / PERCENTAGE_SCALE;
                artistFee =
                    (price * (PERCENTAGE_SCALE - CRATE_FEE_PERCENT)) /
                    PERCENTAGE_SCALE;
                totalPayment = crateFee + artistFee;
            }
        } else if (phase == Phase.BONDING_CURVE) {
            uint256 price = getBuyPrice(_amount);
            tokensInCurve -= _amount;
            crateFee = (price * CRATE_FEE_PERCENT) / PERCENTAGE_SCALE;
            artistFee = (price * ARTIST_FEE_PERCENT) / PERCENTAGE_SCALE;
            totalPayment = price + crateFee + artistFee;
        } else {
            revert WrongPhase();
        }

        artistFees += artistFee;
        // Transfer USDC from buyer to contract
        usdcToken.safeTransferFrom(sender, address(this), totalPayment);

        // Transfer protocol fee to protocolFeeDestination
        usdcToken.safeTransfer(protocolFeeDestination, crateFee);

        _transfer(address(this), sender, _amount);
        emit TokenTrade(sender, _amount, true, totalPayment);

        if (tokensInCurve == 0) {
            phase = Phase.MARKET;
            _addLiquidity();
            emit BondingCurveEnded();
        }
    }

    function sell(
        uint256 _amount,
        uint256 minUsdcReceivable
    ) external nonReentrant {
        address sender = LibMulticaller.sender();

        if (phase != Phase.BONDING_CURVE) revert WrongPhase();
        if (balanceOf(sender) < _amount + crowdfund[sender]) {
            revert InsufficientTokens();
        }
        if (_amount < 10 ** decimals()) revert MustSellAtLeastOneToken();

        uint256 price = getSellPrice(_amount);
        uint256 crateFee = (price * CRATE_FEE_PERCENT) / PERCENTAGE_SCALE;
        uint256 artistFee = (price * ARTIST_FEE_PERCENT) / PERCENTAGE_SCALE;
        artistFees += artistFee;
        uint256 netSellerProceeds = price - crateFee - artistFee;
        if (netSellerProceeds < minUsdcReceivable) {
            revert SlippageToleranceExceeded();
        }

        tokensInCurve += _amount;
        _transfer(sender, address(this), _amount);
        emit TokenTrade(sender, _amount, false, netSellerProceeds);

        // Transfer protocol fee to protocolFeeDestination
        usdcToken.safeTransfer(protocolFeeDestination, crateFee);

        // Transfer net proceeds to seller
        usdcToken.safeTransfer(sender, netSellerProceeds);
    }

    function withdrawArtistFees() public nonReentrant {
        address sender = LibMulticaller.sender();
        if (sender != artistFeeDestination) revert OnlyArtist();
        if (artistFees == 0) revert Zero();
        uint256 fees = artistFees;
        artistFees = 0;
        usdcToken.safeTransfer(artistFeeDestination, fees);
        emit ArtistFeesWithdrawn(artistFeeDestination, fees);
    }

    /// VIEW ///

    function estimateMaxPurchase(
        uint256 usdcAmount
    ) public view returns (uint256) {
        uint256 remainingSupply = tokensInCurve;
        uint256 lower = 0;
        uint256 upper = remainingSupply;
        while (lower < upper) {
            uint256 mid = (lower + upper + 1) / 2;
            if (getBuyPrice(mid) <= usdcAmount) {
                lower = mid;
            } else {
                upper = mid - 1;
            }
        }
        return lower;
    }

    function getBuyPrice(uint256 amount) public view returns (uint256) {
        // Adjusted to output in USDC's 6 decimals
        uint256 price = getPrice(MAX_CURVE_SUPPLY - tokensInCurve, amount);
        return price / 1e12;
    }

    function getSellPrice(uint256 amount) public view returns (uint256) {
        // Adjusted to output in USDC's 6 decimals
        uint256 price = getPrice(
            MAX_CURVE_SUPPLY - tokensInCurve - amount,
            amount
        );
        return price / 1e12;
    }

    function getPrice(
        uint256 supply,
        uint256 amount
    ) private pure returns (uint256) {
        return bondingCurve(supply + amount) - bondingCurve(supply);
    }

    function bondingCurve(uint256 x) public pure returns (uint256) {
        // Adjusted constants for 6 decimals output
        return (x * (x / 1e10 + 1)) / 16e10; // Adjusted denominator
    }

    /// INTERNAL ///

    function _addLiquidity() internal {
        uint256 amountTokenDesired = balanceOf(address(this));
        uint256 amountUsdcDesired = usdcToken.balanceOf(address(this)) -
            artistFees;
        if (amountTokenDesired == 0 || amountUsdcDesired == 0) revert Zero();

        // Calculate the minimum amounts based on a fair price to prevent front-running
        uint256 minTokenPrice = getPrice(MAX_CURVE_SUPPLY, 1e18) / 1e12; // Adjusted for USDC decimals
        uint256 minTokens = (amountUsdcDesired * 1e18) / minTokenPrice; // Result in 18 decimals

        (
            uint256 amountToken,
            uint256 amountUsdc,
            uint256 liquidity
        ) = IUniswapV2Router02(uniswapV2Router02).addLiquidity(
                address(this),
                address(usdcToken),
                amountTokenDesired, // amountTokenDesired
                amountUsdcDesired, // amountUsdcDesired
                minTokens, // amountTokenMin
                amountUsdcDesired, // amountUsdcMin
                address(0), // Send LP tokens to burn address
                block.timestamp // Deadline
            );
        if (amountToken == 0 || amountUsdc == 0 || liquidity == 0) {
            revert Zero();
        }

        emit LiquidityAdded(amountToken, amountUsdc, liquidity);
    }

    function _update(
        address from,
        address to,
        uint256 value
    ) internal override {
        // only allow general transfers in market phase
        if (
            from != address(this) &&
            to != address(this) &&
            (phase != Phase.MARKET)
        ) revert WrongPhase();
        super._update(from, to, value);
    }
}
