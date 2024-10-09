// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockUSDC is ERC20 {
    constructor() ERC20("Mock USDC", "USDC") {
        // _mint(msg.sender, 1_000_000 * 1e6); // Mint 1,000,000 USDC to the deployer
    }

    function decimals() public view virtual override returns (uint8) {
        return 6;
    }
}
