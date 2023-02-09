// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "../contracts/Addresses.sol";

contract FilERC20 {

    using Addresses for *;

    string public constant name = "Example Token";
    string public constant symbol = "EXTOK";
    uint8 public constant decimals = 18;

    mapping(address => uint) balances;
    mapping(address => mapping(address => uint)) allowances;

    uint constant SUPPLY = 1_000_000 * 10e18;

    event Transfer(address indexed _from, address indexed _to, uint256 _value);
    event Approval(address indexed _owner, address indexed _spender, uint256 _value);

    constructor () {
        balances[msg.sender] = SUPPLY;
    }

    function totalSupply() public pure returns (uint) {
        return SUPPLY;
    }

    function transfer(address _to, uint _amt) public returns (bool) {
        // In case _to is an ID address, this attempts to convert to an Eth address
        // If there is no corresponding Eth address, _to remains an ID address
        _to = _to.normalize();
        balances[msg.sender] -= _amt;
        balances[_to] += _amt;

        emit Transfer(msg.sender, _to, _amt);
        return true;
    }
    
    function transferFrom(address _owner, address _to, uint _amt) public returns (bool) {
        // Attempt to normalize both owner and destination
        _owner = _owner.normalize();
        _to = _to.normalize();
        allowances[_owner][msg.sender] -= _amt;
        balances[_owner] -= _amt;
        balances[_to] += _amt;

        emit Approval(_owner, msg.sender, allowances[_owner][msg.sender]);
        emit Transfer(_owner, _to, _amt);
        return true;
    }

    function approve(address _spender, uint _amt) public returns (bool) {
        _spender = _spender.normalize();
        allowances[msg.sender][_spender] = _amt;

        emit Approval(msg.sender, _spender, _amt);
        return true;
    }

    function balanceOf(address _a) public view returns (uint) {
        return balances[_a.normalize()];
    }

    function allowance(address _owner, address _spender) public view returns (uint) {
        return allowances[_owner.normalize()][_spender.normalize()];
    }
}