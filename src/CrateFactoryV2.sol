// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {LibMulticaller} from "@multicaller/LibMulticaller.sol";
import {CrateFactoryV2} from "./CrateFactoryV2.sol";
import {CrateTokenV2} from "./CrateTokenV2.sol";
import {ICrateV2} from "./interfaces/ICrateV2.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

contract CrateFactoryV2 is Ownable2Step, ReentrancyGuard, ICrateV2 {
    address public immutable usdcToken;
    address immutable tokenImplementation;

    uint256 public minCrowdfundGoal = 1000e6; // $1000 in USDC (minimum)
    uint256 public maxCrowdfundGoal = 100_000e6; // $100,000 in USDC (maximum)

    address[] public allTokens;
    uint256 public launchCost;

    event ProtocolFeesWithdrawn(uint256 amount);

    constructor(address _usdcToken) Ownable(msg.sender) {
        launchCost = 99e6; // $99 in USDC TODO: Add feature to get this back
        usdcToken = _usdcToken;
        tokenImplementation = address(new CrateTokenV2());
    }

    function createToken(
        string memory name,
        string memory symbol,
        string memory songURI,
        bytes32 salt,
        uint256 crowdfundGoal
    ) public nonReentrant returns (address) {
        address sender = LibMulticaller.sender();

        if (crowdfundGoal < minCrowdfundGoal || crowdfundGoal > maxCrowdfundGoal) {
            revert InvalidCrowdfundGoal();
        }

        // Check if the user has approved the contract to spend USDC
        uint256 allowance = IERC20(usdcToken).allowance(sender, address(this));
        if (allowance < launchCost) revert InsufficientPayment();

        // Transfer USDC from the sender to the contract
        bool success = IERC20(usdcToken).transferFrom(sender, address(this), launchCost);
        if (!success) revert TransferFailed();

        address clone = Clones.cloneDeterministic(tokenImplementation, _saltedSalt(sender, salt));
        CrateTokenV2 newToken = CrateTokenV2(clone);
        allTokens.push(address(newToken));
        emit TokenLaunched(address(newToken), name, symbol, crowdfundGoal);
        newToken.initialize(usdcToken, name, symbol, address(this), sender, songURI, crowdfundGoal);
        return address(newToken);
    }

    function cancelTokenCrowdfund(address tokenAddress) external onlyOwner {
        CrateTokenV2(tokenAddress).cancelCrowdfund();
    }

    function crateTokenAddress(address owner, bytes32 salt) public view returns (address addr, bool exists) {
        addr = Clones.predictDeterministicAddress(tokenImplementation, _saltedSalt(owner, salt), address(this));
        exists = addr.code.length != 0;
    }

    function _saltedSalt(address owner, bytes32 salt) internal view returns (bytes32 result) {
        assembly {
            mstore(0x20, owner)
            mstore(0x0c, chainid())
            mstore(0x00, salt)
            result := keccak256(0x00, 0x40)
        }
    }

    function updateLaunchCost(uint256 newCost) public onlyOwner {
        launchCost = newCost;
        emit LaunchCostUpdated(newCost);
    }

    function updateCrowdfundGoalLimits(uint256 _minCrowdfundGoal, uint256 _maxCrowdfundGoal) external onlyOwner {
        require(_minCrowdfundGoal <= _maxCrowdfundGoal, "Invalid goal limits");
        minCrowdfundGoal = _minCrowdfundGoal;
        maxCrowdfundGoal = _maxCrowdfundGoal;
        emit CrowdfundGoalUpdated(_minCrowdfundGoal, _maxCrowdfundGoal);
    }

    function withdraw() public onlyOwner {
        uint256 balance = IERC20(usdcToken).balanceOf(address(this));
        bool sent = IERC20(usdcToken).transfer(msg.sender, balance);
        if (!sent) revert TransferFailed();
        emit ProtocolFeesWithdrawn(balance);
    }

    receive() external payable {}
}
