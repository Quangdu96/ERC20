// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MyToken is ERC20, Ownable {
    mapping(address => uint) issuerList; // list of issuers and its allowance

    constructor() ERC20("MyToken", "MTK") {
        uint256 initialSupply = 10000;
        _mint(msg.sender, initialSupply);
    }

    function registerIssuer(address issuer, uint allowance) external onlyOwner {
        approve(issuer, allowance);
        issuerList[issuer] = allowance;
    }
}
