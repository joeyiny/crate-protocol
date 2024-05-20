// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "./CrateTokenV1.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../lib/multicaller/src/LibMulticaller.sol";

contract CrateFactoryV1 is Ownable2Step, ReentrancyGuard {
    event TokenLaunched(address tokenAddress, string name, string symbol);
    event LaunchCostUpdated(uint256 newCost);

    address[] public allTokens;

    address immutable tokenImplementation;

    address public immutable uniswapV2Router02;
    uint256 public launchCost = 0.00125 ether;

    constructor(address _uniswapV2Router) Ownable(msg.sender) {
        uniswapV2Router02 = _uniswapV2Router;
        tokenImplementation = address(new CrateTokenV1());
    }

    function createToken(string memory name, string memory symbol, string memory songURI, bytes32 salt)
        public
        payable
        nonReentrant
        returns (address)
    {
        address sender = LibMulticaller.sender();

        require(msg.value == launchCost, "Did not send correct launch cost.");
        address clone = Clones.cloneDeterministic(tokenImplementation, _saltedSalt(sender, salt));
        CrateTokenV1 newToken = CrateTokenV1(clone);
        allTokens.push(address(newToken));
        emit TokenLaunched(address(newToken), name, symbol);
        newToken.initialize(uniswapV2Router02, name, symbol, address(this), sender, songURI);

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

    function withdraw() public {
        (bool sent,) = owner().call{value: address(this).balance}("");
        require(sent, "Failed to send Ether");
    }

    receive() external payable {}
}
