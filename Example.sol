// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "./contracts/utils/FilAddress.sol";

contract BadBank {
    mapping(address => uint) balances;

    // Send a deposit to someone's account
    function deposit(address _account) public payable {
        balances[_account] += msg.value;
    }

    // Withdraw from your own account
    function withdraw() public {
        uint amount = balances[msg.sender];
        balances[msg.sender] = 0;

        msg.sender.call{value: amount}("");
    }
}

contract GoodBank {

    using FilAddress for *;

    mapping(address => uint) balances;

    // Send a deposit to someone's account
    function deposit(address _account) public payable {
        _account = _account.normalize();
        balances[_account] += msg.value;
    }

    // Withdraw from your own account
    function withdraw() public {
        uint amount = balances[msg.sender];
        balances[msg.sender] = 0;

        msg.sender.call{value: amount}("");
    }
}