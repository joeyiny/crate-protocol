//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20Upgradeable} from "@openzeppelin-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {LibMulticaller} from "@multicaller/LibMulticaller.sol";
import {ICrateV2} from "./interfaces/ICrateV2.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

/**
 * This is a crowdfunded token launch.
 * Users crowdfund and receive nontransferable tokens.
 */
contract CrowdfundToken is ERC20Upgradeable, ReentrancyGuard, ICrateV2 {
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
        uint256 tokenSupply = calculateTokenPurchaseAmount(_crowdfundGoal);
        _mint(address(this), tokenSupply);
    }

    modifier onlyPhase(Phase _requiredPhase) {
        require(phase == _requiredPhase, "Incorrect phase");
        _;
    }

    /// PUBLIC ///

    function fund(uint256 _usdcAmount) public nonReentrant onlyPhase(Phase.CROWDFUND) {
        if (_usdcAmount == 0) revert Zero();

        bool willFinishCrowdfundFlag = false;
        uint256 amountNeeded = _usdcAmount;

        if (_usdcAmount + amountRaised >= crowdfundGoal) {
            amountNeeded = crowdfundGoal - amountRaised;
            willFinishCrowdfundFlag=true;
        }

        address sender = LibMulticaller.sender();

        // User must approve the contract to transfer USDC on their behalf
        require(IERC20(usdcToken).allowance(sender, address(this)) >= amountNeeded, "USDC allowance too low");

        // Transfer USDC from sender to this contract
        bool success = IERC20(usdcToken).transferFrom(sender, address(this), amountNeeded);
        require(success, "USDC transfer failed");

        // Calculate amount of tokens earned
        uint256 numTokens = calculateTokenPurchaseAmount(amountNeeded);

        amountRaised += amountNeeded;
        crowdfundTokens[sender] += numTokens;
        amountPaid[sender] += amountNeeded;
        tokensSold += numTokens;

        //Transfer Tokens
        _transfer(address(this), sender, numTokens);

        // Calculate fees
        uint256 protocolFee = (amountNeeded * 10) / 100;
        uint256 artistFee = amountNeeded - protocolFee;

        artistCrowdfundFees += artistFee;
        protocolCrowdfundFees += protocolFee;

     
        if(willFinishCrowdfundFlag==true) {
            _enterPhasePending();
        }

        emit Fund(sender, amountNeeded, numTokens);
    }

    function completeCrowdfund() external nonReentrant onlyPhase(Phase.PENDING) {
        require(msg.sender == protocolFeeDestination, "Not authorized.");

        phase = Phase.COMPLETED;
        _transferProtocolFees();
        emit EnterPhase(phase);
    }

    /**
     * @notice Allows the cancellation of an ongoing crowdfund, providing refunds to all participants and preventing the distribution of tokens.
     *
     * @dev The purpose of this function is to improve the UX by offering a way to safely cancel a crowdfund when necessary.
     * Without this function, crowdfunds could be stuck in limbo if the goal is never met. Also, we need a protection against malicious activity.
     */
    function cancelCrowdfund() external nonReentrant {
        require(msg.sender == artistFeeDestination || msg.sender == protocolFeeDestination, "Not authorized.");
        require(
            phase == Phase.CROWDFUND || phase == Phase.PENDING, "This token is not in the correct phase, cannot cancel."
        );

        phase = Phase.CANCELED;
        protocolCrowdfundFees = 0;
        artistCrowdfundFees = 0;
        emit EnterPhase(phase);
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
        require(phase == Phase.COMPLETED, "Can't withdraw in this phase.");
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

    function _enterPhasePending() private onlyPhase(Phase.CROWDFUND) {
        phase = Phase.PENDING;
        emit EnterPhase(phase);
    }

    function _transferProtocolFees() private onlyPhase(Phase.COMPLETED) {
        require(protocolCrowdfundFees > 0, "There are no protocol fees accumulated.");
        bool protocolFeePaid = IERC20(usdcToken).transfer(protocolFeeDestination, protocolCrowdfundFees);
        if (!protocolFeePaid) revert TransferFailed();
        emit ProtocolFeesPaid(protocolCrowdfundFees);
        protocolCrowdfundFees = 0;
    }

    /// VIEW ///

    function calculateTokenPurchaseAmount(uint256 _usdcAmount) public pure returns (uint256) {
        uint256 initialPrice = getInitialPrice();
        uint256 tokenAmount = (_usdcAmount * 1e18) / initialPrice;
        return tokenAmount;
    }

    function getInitialPrice() public pure returns (uint256) {
        return 5e6; // $5 per token
    }

    /// INTERNAL ///

    function _update(address from, address to, uint256 value) internal override {
        if (phase == Phase.CROWDFUND) {
            // Allow only transfers from the contract (e.g., distributing tokens to funders)
            if (from == address(this) || from == address(0)) {
                super._update(from, to, value);
                return;
            } else {
                revert("Transfers not allowed during crowdfund phase");
            }
        } else if (phase == Phase.CANCELED) {
            //tokens can be burned if crowdfund is canceled
            if (to == address(0) || to == address(this)) {
                super._update(from, to, value);
                return;
            } else {
                revert("Transfers not allowed during canceled phase");
            }
        } else if (phase == Phase.PENDING) {
            if (from == address(this) || from == address(0) || to == address(0) || to == address(this)) {
                super._update(from, to, value);
                return;
            } else {
                revert("Transfers not allowed during pending phase");
            }
        }
        super._update(from, to, value);
    }
}
