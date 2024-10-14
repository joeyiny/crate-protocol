//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {ERC20Upgradeable} from "@openzeppelin-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {LibMulticaller} from "@multicaller/LibMulticaller.sol";
import {IUniswapV2Router02} from "src/interfaces/IUniswapV2RouterV2.sol";
import {ICrateV2} from "src/interfaces/ICrateV2.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

// The total supply is 117,000 tokens
// Once the bonding curve has sold out 80,000 tokens, the other 37,000 are put in Uniswap with the total ETH in the contract.
// The LP tokens are then burned, so no one can pull the liquidity.
contract CrateTokenV2 is ERC20Upgradeable, ReentrancyGuard, ICrateV2 {
    uint256 private constant MAX_SUPPLY = 117_000e18;
    uint256 private constant MAX_CURVE_SUPPLY = 80_000e18;
    uint256 private constant CROWDFUND_THRESHOLD = 60_000e18;
    uint256 private constant CRATE_FEE_PERCENT = 5e15;
    uint256 private constant ARTIST_FEE_PERCENT = 5e15;

    uint256 public constant CROWDFUND_GOAL = 5000 * 1e6;

    address public uniswapV2Router02;
    address public usdcToken;
    address public protocolFeeDestination;
    address public artistFeeDestination;

    uint256 public tokensInCurve;

    uint256 public protocolFees;
    uint256 public artistFees;
    uint256 public amountRaised;
    uint256 public artistCrowdfundFees; //The artist can only pull this when the crowdfund is complete, because refunds are still possible.

    mapping(address => uint256) public crowdfundTokens; //This is the amount of tokens users have bought in the crowdfund phase. This is to handle crowdfund cancels/refunds.
    mapping(address => uint256) public amountPaid; //This is the amount of money users have sent in the crowdfund phase. This is to handle crowdfund cancels/refunds.

    string public songURI;

    Phase public phase;

    address[] private crowdfundParticipants;

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _uniswapV2Router02,
        address _usdcToken,
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
        usdcToken = _usdcToken;
        phase = Phase.CROWDFUND;
        tokensInCurve = MAX_CURVE_SUPPLY;
        songURI = _songURI;
        _approve(address(this), uniswapV2Router02, MAX_SUPPLY);
    }

    /// PUBLIC ///

    function fund(uint256 _usdcAmount) public nonReentrant {
        // require(_usdcAmount >= 1 * 1e6, "Cannot pay less than $1");
        if (phase != Phase.CROWDFUND) revert WrongPhase();
        require(_usdcAmount > 0, "Must donate more than 0");

        // Update phase
        // TODO: Handle the excess going into the bonding curve
        if (_usdcAmount + amountRaised >= CROWDFUND_GOAL) {
            _usdcAmount = CROWDFUND_GOAL - amountRaised;
            phase = Phase.BONDING_CURVE;
            emit CrowdfundCompleted();
        }

        // require(_usdcAmount >= 1 * 1e6, "Cannot pay less than $1");
        address sender = LibMulticaller.sender();
        // User must approve the contract to transfer USDC on their behalf
        require(IERC20(usdcToken).allowance(sender, address(this)) >= _usdcAmount, "USDC allowance too low");

        // Transfer USDC from sender to this contract
        bool success = IERC20(usdcToken).transferFrom(sender, address(this), _usdcAmount);
        require(success, "USDC transfer failed");

        // Calculate amount of tokens earned
        uint256 numTokens = calculateTokenAmount(_usdcAmount);
        require(numTokens > 0, "Cannot buy 0 tokens");

        amountRaised += _usdcAmount;
        crowdfundTokens[sender] += numTokens; //Keep track of how many tokens this user purchased in the bonding curve
        amountPaid[sender] += _usdcAmount;
        crowdfundParticipants.push(sender);
        _transfer(address(this), sender, numTokens);

        // Calculate fees
        uint256 protocolFee = (_usdcAmount * 10) / 100;
        uint256 artistFee = _usdcAmount - protocolFee;

        artistCrowdfundFees += artistFee;
        protocolFees += protocolFee;

        // TODO: Switch pattern to accumulate/withdraw
        emit Fund(sender, _usdcAmount, numTokens);
        // require(IERC20(usdcToken).transfer(artistFeeDestination, artistFee), "Artist fee transfer failed");
    }

    //TODO: make this onlyOwner/onlyArtist
    function cancelCrowdfund() external nonReentrant {
        require(phase == Phase.CROWDFUND, "This token is no longer in the Crowdfund phase, cannot cancel.");

        phase = Phase.CANCELED;
        protocolFees = 0;
        artistFees = 0;

        for (uint256 i = 0; i < crowdfundParticipants.length; i++) {
            address user = crowdfundParticipants[i];
            uint256 userAmountPaid = amountPaid[user];
            uint256 userTokens = crowdfundTokens[user];

            // Reset user's state
            amountPaid[user] = 0;
            crowdfundTokens[user] = 0;

            // Refund USDC
            require(IERC20(usdcToken).transfer(user, userAmountPaid), "USDC refund failed");

            // Destroy tokens
            _burn(user, userTokens);
        }
        emit CrowdfundCanceled();
    }

    function calculateTokenAmount(uint256 _usdcAmount) public pure returns (uint256) {
        uint256 donationPrice = getDonationPrice();
        uint256 tokenAmount = (_usdcAmount * 1e18) / donationPrice;
        return tokenAmount;
    }

    function getDonationPrice() public pure returns (uint256) {
        return 5 * 1e6; //$5 per copy
    }

        uint256 tokensToBuy = estimateMaxPurchase(netValue);
        if (tokensToBuy == 0) revert Zero();
        if (tokensToBuy < minTokensReceivable) {
            revert SlippageToleranceExceeded();
        }
        buy(tokensToBuy);
    }

    function buy(uint256 _amount) public payable nonReentrant {
        if (phase != Phase.BONDING_CURVE) revert WrongPhase();

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
        if (balanceOf(sender) < _amount + crowdfundTokens[sender]) revert InsufficientTokens();
        if (_amount < 10 ** decimals()) revert MustSellAtLeastOneToken();

        uint256 price = getSellPrice(_amount);
        uint256 crateFee = (price * CRATE_FEE_PERCENT) / 1 ether;
        uint256 artistFee = (price * ARTIST_FEE_PERCENT) / 1 ether;
        artistFees += artistFee;
        uint256 netSellerProceeds = price - crateFee - artistFee;
        if (netSellerProceeds < minEtherReceivable) {
            revert SlippageToleranceExceeded();
        }

        tokensInCurve += _amount;
        _transfer(sender, address(this), _amount);
        emit TokenTrade(sender, _amount, false, netSellerProceeds);

        (bool netProceedsSent,) = (sender).call{value: netSellerProceeds}("");
        if (!netProceedsSent) revert TransferFailed();

        (bool crateFeePaid,) = protocolFeeDestination.call{value: crateFee}("");
        if (!crateFeePaid) revert TransferFailed();
    }

    function withdrawArtistFees() public nonReentrant {
        require(phase != Phase.CROWDFUND, "Cannot withdraw artist fees in the Crowdfund phase.");
        address sender = LibMulticaller.sender();
        if (sender != artistFeeDestination) revert OnlyArtist();
        if (artistCrowdfundFees == 0) revert Zero();
        uint256 fees = artistCrowdfundFees;
        artistCrowdfundFees = 0;
        bool artistFeePaid = IERC20(usdcToken).transfer(artistFeeDestination, fees);
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
        //tokens can be burned if crowdfund is canceled
        if (to == address(0) && phase == Phase.CANCELED) {
            super._update(from, to, value);
            return;
        }
        // only allow general transfers in market phase
        if (from != address(this) && to != address(this) && (phase != Phase.MARKET)) revert WrongPhase();
        super._update(from, to, value);
    }
}
