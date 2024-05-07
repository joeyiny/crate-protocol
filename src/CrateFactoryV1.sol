// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "./CrateTokenV1.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract CrateFactoryV1 is Ownable, ReentrancyGuard {
    event TokenLaunched(address tokenAddress, string name, string symbol);
    event LaunchCostUpdated(uint256 newCost);
    address[] public allTokens;

    address immutable tokenImplementation;

    address public immutable uniswapV2Router02;
    uint256 public launchCost = 0.00125 ether;

    constructor(address _uniswapV2Router) Ownable(msg.sender) {
        require(
            _uniswapV2Router != address(0),
            "UniswapV2 Router address cannot be zero"
        );

        uniswapV2Router02 = _uniswapV2Router;
        tokenImplementation = address(new CrateTokenV1());
    }

    function createToken(
        string memory name,
        string memory symbol,
        string memory songURI,
        bytes32 salt
    ) public payable nonReentrant returns (address) {
        require(msg.value >= launchCost, "Insufficient ETH sent.");
        address clone = Clones.cloneDeterministic(tokenImplementation, salt);
        CrateTokenV1 newToken = CrateTokenV1(clone);
        allTokens.push(address(newToken));
        emit TokenLaunched(address(newToken), name, symbol);
        newToken.initialize(
            uniswapV2Router02,
            name,
            symbol,
            address(this),
            msg.sender,
            songURI
        );

        // Refund any excess ETH sent with the transaction
        uint256 excess = msg.value - launchCost;
        if (excess > 0) {
            (bool sent, ) = msg.sender.call{value: excess}("");
            require(sent, "Failed to refund excess ETH");
        }

        return address(newToken);
    }

    function crateTokenAddress(
        bytes32 salt
    ) public view returns (address addr, bool exists) {
        addr = Clones.predictDeterministicAddress(tokenImplementation, salt);
        exists = addr.code.length != 0;
    }

    function updateLaunchCost(uint256 newCost) public onlyOwner {
        launchCost = newCost;
        emit LaunchCostUpdated(newCost);
    }

    function withdraw() public onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }

    receive() external payable {}
}
