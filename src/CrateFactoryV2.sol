// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {LibMulticaller} from "@multicaller/LibMulticaller.sol";
import {CrateFactoryV2} from "./CrateFactoryV2.sol";
import {CrateTokenV2} from "./CrateTokenV2.sol";
import {ICrateV2} from "./interfaces/ICrateV2.sol";

contract CrateFactoryV2 is Ownable2Step, ReentrancyGuard, ICrateV2 {
    address public immutable uniswapV2Router02;
    address public immutable usdcToken;
    address immutable tokenImplementation;

    address[] public allTokens;
    uint256 public launchCost;

    constructor(address _uniswapV2Router, address _usdcToken) Ownable(msg.sender) {
        launchCost = 0.04 ether;
        uniswapV2Router02 = _uniswapV2Router;
        usdcToken = _usdcToken;
        tokenImplementation = address(new CrateTokenV2());
    }

    function createToken(string memory name, string memory symbol, string memory songURI, bytes32 salt)
        public
        payable
        nonReentrant
        returns (address)
    {
        address sender = LibMulticaller.sender();
        if (msg.value < launchCost) revert InsufficientPayment();
        address clone = Clones.cloneDeterministic(tokenImplementation, _saltedSalt(sender, salt));
        CrateTokenV2 newToken = CrateTokenV2(clone);
        allTokens.push(address(newToken));
        emit TokenLaunched(address(newToken), name, symbol);
        newToken.initialize(uniswapV2Router02, usdcToken, name, symbol, address(this), sender, songURI);
        return address(newToken);
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

    function withdraw() public onlyOwner {
        (bool sent,) = owner().call{value: address(this).balance}("");
        if (!sent) revert TransferFailed();
    }

    receive() external payable {}
}
