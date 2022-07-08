//SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

contract PlayToken is ERC20, Ownable, Pausable {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) { }

    function mint(address account, uint256 amount) public onlyOwner {
        super._mint(account, amount);
    }

    function toEth(uint256 amount) public {
        super._burn(msg.sender, amount);

        payable(msg.sender).send(amount);
    }

    function toToken() public payable {
        super._mint(msg.sender, msg.value);
    }
}
