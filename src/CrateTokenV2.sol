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
    uint256 private constant MAX_SUPPLY = 5_000e18;

    //TODO: Let user set this
    uint256 public constant CROWDFUND_GOAL = 5000 * 1e6;

    address public uniswapV2Router02;
    address public usdcToken;
    address public protocolFeeDestination;
    address public artistFeeDestination;

    uint256 public unsoldTokens;

    uint256 public artistCrowdfundFees; //The artist can only withdraw this when the crowdfund is complete.
    uint256 public protocolFees;
    uint256 public amountRaised;


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
        unsoldTokens = MAX_SUPPLY;
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

        // Temporarily removed: TODO: Fix this and handle crowdfund being stuck issue
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

        //Handle global state manipulation
        unsoldTokens -= numTokens;
        amountRaised += _usdcAmount;
        crowdfundTokens[sender] += numTokens; //Keep track of how many tokens this user purchased in the bonding curve
        amountPaid[sender] += _usdcAmount;
        crowdfundParticipants.push(sender);

        //Transfer Tokens
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
    /**
     * @notice Allows the cancellation of an ongoing crowdfund, providing refunds to all participants and preventing the distribution of tokens.
     *
     * @dev The purpose of this function is to improve the UX by offering a way to safely cancel a crowdfund when necessary.
     * Without this function, crowdfunds could be stuck in limbo if the goal is never met. Also, we need a protection against malicious activity.
     */
    function cancelCrowdfund() external nonReentrant {
        require(phase == Phase.CROWDFUND, "This token is no longer in the Crowdfund phase, cannot cancel.");

        phase = Phase.CANCELED;
        protocolFees = 0;
        artistCrowdfundFees = 0;

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

    function withdrawProtocolFees() public nonReentrant {
        require(phase != Phase.CROWDFUND, "Cannot withdraw protocol fees in the Crowdfund phase.");
        if (protocolFees == 0) revert Zero();
        uint256 fees = protocolFees;
        protocolFees = 0;
        bool protocolFeePaid = IERC20(usdcToken).transfer(protocolFeeDestination, fees);
        if (!protocolFeePaid) revert TransferFailed();
        emit ProtocolFeesWithdrawn(fees);
    }

    /// VIEW ///

    function calculateTokenAmount(uint256 _usdcAmount) public pure returns (uint256) {
        uint256 donationPrice = getDonationPrice();
        uint256 tokenAmount = (_usdcAmount * 1e18) / donationPrice;
        return tokenAmount;
    }

    function getDonationPrice() public pure returns (uint256) {
        return 5 * 1e6; //$5 per copy
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
