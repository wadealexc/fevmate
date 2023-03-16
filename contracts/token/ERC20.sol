// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "../utils/FilAddress.sol";

/**
 * @author fevmate (https://github.com/wadealexc/fevmate)
 * @notice ERC20 mixin for the FEVM. This contract implements the ERC20
 * standard, with additional safety features for the FEVM.
 *
 * All methods attempt to normalize address input. This means that if
 * they are provided ID addresses as input, they will attempt to convert
 * these addresses to standard Eth addresses. 
 * 
 * This is an important consideration when developing on the FEVM, and
 * you can read about it more in the README.
 */
abstract contract ERC20 {

    using FilAddress for *;

    /*//////////////////////////////////////
                  TOKEN INFO
    //////////////////////////////////////*/

    string public name;
    string public symbol;
    uint8 public decimals;

    /*//////////////////////////////////////
                 ERC-20 STORAGE
    //////////////////////////////////////*/

    uint public totalSupply;

    mapping(address => uint) balances;
    mapping(address => mapping(address => uint)) allowances;

    /*//////////////////////////////////////
                    EVENTS
    //////////////////////////////////////*/

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    /*//////////////////////////////////////
                  CONSTRUCTOR
    //////////////////////////////////////*/

    constructor (
        string memory _name, 
        string memory _symbol, 
        uint8 _decimals
    ) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }

    /*//////////////////////////////////////
                 ERC-20 METHODS
    //////////////////////////////////////*/

    function transfer(address _to, uint _amount) public virtual returns (bool) {
        // Attempt to convert destination to Eth address
        _to = _to.normalize();
        
        balances[msg.sender] -= _amount;
        balances[_to] += _amount;

        emit Transfer(msg.sender, _to, _amount);
        return true;
    }
    
    function transferFrom(address _owner, address _to, uint _amount) public virtual returns (bool) {
        // Attempt to convert owner and destination to Eth addresses
        _owner = _owner.normalize();
        _to = _to.normalize();

        // Reduce allowance for spender. If allowance is set to the
        // max value, we leave it alone.
        uint allowed = allowances[_owner][msg.sender];
        if (allowed != type(uint).max)
            allowances[_owner][msg.sender] = allowed - _amount;
        
        balances[_owner] -= _amount;
        balances[_to] += _amount;

        emit Transfer(_owner, _to, _amount);
        return true;
    }

    function approve(address _spender, uint _amount) public virtual returns (bool) {
        // Attempt to convert spender to Eth address
        _spender = _spender.normalize();

        allowances[msg.sender][_spender] = _amount;

        emit Approval(msg.sender, _spender, _amount);
        return true;
    }

    /*//////////////////////////////////////
                 ERC-20 GETTERS
    //////////////////////////////////////*/

    function balanceOf(address _a) public virtual view returns (uint) {
        return balances[_a.normalize()];
    }

    function allowance(address _owner, address _spender) public virtual view returns (uint) {
        return allowances[_owner.normalize()][_spender.normalize()];
    }

    /*//////////////////////////////////////
           MINT/BURN INTERNAL METHODS
    //////////////////////////////////////*/

    function _mint(address _to, uint _amount) internal virtual {
        // Attempt to convert to Eth address
        _to = _to.normalize();

        totalSupply += _amount;
        balances[_to] += _amount;

        emit Transfer(address(0), _to, _amount);
    }

    function _burn(address _from, uint _amount) internal virtual {
        // Attempt to convert to Eth address
        _from = _from.normalize();

        balances[_from] -= _amount;
        totalSupply -= _amount;

        emit Transfer(_from, address(0), _amount);
    }
}