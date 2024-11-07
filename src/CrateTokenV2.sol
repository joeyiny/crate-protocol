//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20Upgradeable} from "@openzeppelin-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {LibMulticaller} from "@multicaller/LibMulticaller.sol";
import {IUniswapV2Router02} from "./interfaces/IUniswapV2RouterV2.sol";
import {ICrateV2} from "./interfaces/ICrateV2.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

/**
 * This is a crowdfunded token launch.
 *     Users crowdfund and receive nontransferable tokens. Once the goal is hit, then the tokens become transferable and a market is launched for the tokens.
 */
contract CrateTokenV2 is ERC20Upgradeable, ReentrancyGuard, ICrateV2 {
    //IMMUTABLE
    address public usdcToken;
    address public protocolFeeDestination;
    address public artistFeeDestination;
    string public songURI;
    uint256 public crowdfundGoal; // USDC with 6 decimals.

    //CROWDFUND
    Phase public phase;
    uint256 public artistCrowdfundFees; //The artist can only withdraw this when the crowdfund is complete.
    uint256 public protocolCrowdfundFees;
    uint256 public amountRaised;
    uint256 public tokensSold;

    //USERS
    mapping(address => uint256) public crowdfundTokens; //This is the amount of tokens users have bought in the crowdfund phase. This is to handle crowdfund cancels/refunds.
    mapping(address => uint256) public amountPaid; //This is the amount of money users have sent in the crowdfund phase. This is to handle crowdfund cancels/refunds.
    mapping(address => bool) public refundClaimed;

    //AMM
    BondingCurve public curve;

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _usdcToken,
        string memory _name,
        string memory _symbol,
        address _protocolAddress,
        address _artistAddress,
        string memory _songURI,
        uint256 _crowdfundGoal
    ) public initializer {
        __ERC20_init(_name, _symbol);
        artistFeeDestination = _artistAddress;
        protocolFeeDestination = _protocolAddress;
        usdcToken = _usdcToken;
        phase = Phase.CROWDFUND;
        songURI = _songURI;
        crowdfundGoal = _crowdfundGoal;
        crowdfundStartTime = block.timestamp;
        _mint(address(this), getMaxSupply());
    }

    modifier onlyPhase(Phase _requiredPhase) {
        require(phase == _requiredPhase, "Incorrect phase");
        _;
    }

    /// PUBLIC ///

    function fund(uint256 _usdcAmount) public nonReentrant onlyPhase(Phase.CROWDFUND) {
        if (_usdcAmount == 0) revert Zero();

        uint256 amountNeeded = _usdcAmount;
        // Update phase
        // TODO: Handle the excess going into the bonding curve
        if (_usdcAmount + amountRaised >= crowdfundGoal) {
            amountNeeded = crowdfundGoal - amountRaised;
            _beginBondingCurve();
        }

        // Temporarily removed: TODO: Fix this and handle crowdfund being stuck issue
        address sender = LibMulticaller.sender();
        // require(_usdcAmount >= 1 * 1e6, "Cannot pay less than $1");

        // User must approve the contract to transfer USDC on their behalf
        require(IERC20(usdcToken).allowance(sender, address(this)) >= amountNeeded, "USDC allowance too low");

        // Transfer USDC from sender to this contract
        bool success = IERC20(usdcToken).transferFrom(sender, address(this), amountNeeded);
        require(success, "USDC transfer failed");

        // Calculate amount of tokens earned
        uint256 numTokens = calculateTokenPurchaseAmount(amountNeeded);

        //Handle global state manipulation
        amountRaised += amountNeeded;
        crowdfundTokens[sender] += numTokens; //Keep track of how many tokens this user purchased in the bonding curve
        amountPaid[sender] += amountNeeded;
        tokensSold += numTokens;

        //Transfer Tokens
        _transfer(address(this), sender, numTokens);

        // Calculate fees
        uint256 protocolFee = (amountNeeded * 10) / 100;
        uint256 artistFee = amountNeeded - protocolFee;

        artistCrowdfundFees += artistFee;
        protocolCrowdfundFees += protocolFee;

        if (phase == Phase.BONDING_CURVE) {
            if (protocolCrowdfundFees > 0) {
                bool protocolFeePaid = IERC20(usdcToken).transfer(protocolFeeDestination, protocolCrowdfundFees);
                if (!protocolFeePaid) revert TransferFailed();
                emit ProtocolFeesPaid(protocolCrowdfundFees);
                protocolCrowdfundFees = 0;
            }
        }
        emit Fund(sender, amountNeeded, numTokens);
    }

    function buy(uint256 _usdcAmount) public nonReentrant onlyPhase(Phase.BONDING_CURVE) {
        if (_usdcAmount == 0) revert Zero();
        address sender = LibMulticaller.sender();
        require(IERC20(usdcToken).balanceOf(sender) >= _usdcAmount, "USDC allowance too low");
        require(IERC20(usdcToken).allowance(sender, address(this)) >= _usdcAmount, "USDC allowance too low");
        uint256 numTokens = _calculateAmmTokenOut(_usdcAmount);
        require(curve.tokenAmount >= numTokens, "Not enough tokens in curve.");
        // Transfer USDC from sender to this contract
        bool success = IERC20(usdcToken).transferFrom(sender, address(this), _usdcAmount);
        require(success, "USDC transfer failed");

        curve.tokenAmount -= numTokens;
        curve.usdcAmount += _usdcAmount;
        //Transfer Tokens
        _transfer(address(this), sender, numTokens);
        emit TokenPurchase(sender, _usdcAmount, numTokens);
    }

    function sell(uint256 _tokenAmount) public nonReentrant onlyPhase(Phase.BONDING_CURVE) {
        if (_tokenAmount == 0) revert Zero();
        address sender = LibMulticaller.sender();
        require(balanceOf(sender) >= _tokenAmount, "Insufficient token balance");
        uint256 numUsdc = _calculateAmmUsdcOut(_tokenAmount);
        require(curve.usdcAmount >= numUsdc, "Not enough liquidity.");
        curve.tokenAmount += _tokenAmount;
        curve.usdcAmount -= numUsdc;
        _transfer(sender, address(this), _tokenAmount);
        bool success = IERC20(usdcToken).transfer(sender, numUsdc);
        require(success, "USDC transfer failed");
        emit TokenSale(sender, _tokenAmount, numUsdc);
    }

    /**
     * @notice Allows the cancellation of an ongoing crowdfund, providing refunds to all participants and preventing the distribution of tokens.
     *
     * @dev The purpose of this function is to improve the UX by offering a way to safely cancel a crowdfund when necessary.
     * Without this function, crowdfunds could be stuck in limbo if the goal is never met. Also, we need a protection against malicious activity.
     */
    function cancelCrowdfund() external nonReentrant onlyPhase(Phase.CROWDFUND) {
        require(msg.sender == artistFeeDestination || msg.sender == protocolFeeDestination, "Not authorized.");
        require(phase == Phase.CROWDFUND, "This token is no longer in the Crowdfund phase, cannot cancel.");

        phase = Phase.CANCELED;
        protocolCrowdfundFees = 0;
        artistCrowdfundFees = 0;
        emit CrowdfundCanceled();
    }

    function claimRefund() external nonReentrant {
        require(phase == Phase.CANCELED, "Crowdfund not canceled");
        require(!refundClaimed[msg.sender], "Refund already claimed");
        uint256 userAmountPaid = amountPaid[msg.sender];
        uint256 userTokens = crowdfundTokens[msg.sender];
        require(userAmountPaid > 0, "No funds to refund");

        refundClaimed[msg.sender] = true;
        amountPaid[msg.sender] = 0;
        crowdfundTokens[msg.sender] = 0;

        // Refund USDC
        bool success = IERC20(usdcToken).transfer(msg.sender, userAmountPaid);
        require(success, "USDC refund failed");
        emit ClaimRefund(msg.sender, userAmountPaid);

        // Burn tokens
        _burn(msg.sender, userTokens);
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

    /// PRIVATE ///

    function _beginBondingCurve() private onlyPhase(Phase.CROWDFUND) {
        curve.tokenAmount = 1000e18;
        curve.usdcAmount = 0;
        curve.virtualUsdcAmount = 5000e6;
        phase = Phase.BONDING_CURVE;
        emit StartBondingCurve(curve.tokenAmount, curve.usdcAmount, curve.virtualUsdcAmount);
    }

    /// VIEW ///

    function calculateTokenPurchaseAmount(uint256 _usdcAmount) public view returns (uint256) {
        uint256 donationPrice = getInitialPrice();
        uint256 tokenAmount = (_usdcAmount * 1e18) / donationPrice;
        return tokenAmount;
    }

    function getInitialPrice() public view returns (uint256) {
        return crowdfundGoal / 1000; // eg, $5k goal means $5 token price.
    }

    function getCurrentPrice() public view returns (uint256) {
        // Adjust USDC reserve to 18 decimals (from 6 decimals in USDC)
        uint256 usdcReserve = (curve.usdcAmount + curve.virtualUsdcAmount) * 1e12;
        uint256 tokenReserve = curve.tokenAmount; // Already in 18 decimals

        // Ensure token reserve is not zero to prevent division by zero
        require(tokenReserve > 0, "Token reserve is zero");

        // Price per token in USDC (18 decimals)
        // Multiply by 1e18 to preserve precision before dividing
        uint256 pricePerToken = (usdcReserve * 1e18) / tokenReserve;

        return pricePerToken; // This will be in 18 decimals
    }

    function _calculateAmmTokenOut(uint256 usdcIn) internal view returns (uint256) {
        uint256 k = (curve.virtualUsdcAmount + curve.usdcAmount) * curve.tokenAmount;
        uint256 newUsdcAmount = curve.virtualUsdcAmount + curve.usdcAmount + usdcIn;
        return curve.tokenAmount - (k / newUsdcAmount);
    }

    function _calculateAmmUsdcOut(uint256 tokenIn) internal view returns (uint256) {
        uint256 k = (curve.virtualUsdcAmount + curve.usdcAmount) * curve.tokenAmount;
        uint256 newTokenAmount = curve.tokenAmount + tokenIn;
        return (curve.virtualUsdcAmount + curve.usdcAmount) - (k / newTokenAmount);
    }

    // Function to calculate max supply based on the crowdfund goal.
    function getMaxSupply() public view returns (uint256) {
        return crowdfundGoal * 1e12; // Convert USDC (6 decimals) to max supply (18 decimals).
    }

    /// INTERNAL ///

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
