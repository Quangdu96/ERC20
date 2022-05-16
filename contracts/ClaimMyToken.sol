// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./MyToken.sol";

contract ClaimMyToken {
	MyToken MTKContract;
	constructor(address MTKAddress) {
		MTKContract = MyToken(MTKAddress);
	}

    event Claim(address indexed claimer, uint amount);

	function claim(uint amount) external {
		MTKContract.transferFrom(MTKContract.owner(), msg.sender, amount);
		emit Claim(msg.sender, amount);
	}
}
