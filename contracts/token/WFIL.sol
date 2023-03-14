// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./ERC20.sol";
import "../utils/FilAddress.sol";
import "../access/OwnedClaimable.sol";

/**
 * @author fevmate
 * @notice Wrapped Filecoin implementation, using ERC20-FEVM mixin.
 */
contract WFIL is ERC20("Wrapped Filecoin", "WFIL", 18), OwnedClaimable {

    using FilAddress for *;

    /*//////////////////////////////////////
                    EVENTS
    //////////////////////////////////////*/

    event Deposit(address indexed from, uint amount);
    event Withdrawal(address indexed to, uint amount);

    /*//////////////////////////////////////
                  WFIL METHODS
    //////////////////////////////////////*/

    function deposit() public payable virtual {
        _mint(msg.sender, msg.value);

        emit Deposit(msg.sender, msg.value);
    }

    function withdraw(uint _amount) public virtual {
        _burn(msg.sender, _amount);

        emit Withdrawal(msg.sender, _amount);

        payable(msg.sender).sendValue(_amount);
    }

    receive() external payable virtual {
        deposit();
    }

    function escapeLockedTokens(address _target, uint _amount) public virtual onlyOwner {
        // Calculate amount of locked Fil
        uint lockedFil = address(this).balance - totalSupply();
        require(_amount <= lockedFil);

        payable(_target).sendValue(_amount);
    }

    function recoverDeposit(address _depositor, uint _amount) public virtual onlyOwner {
        // Calculate number of locked tokens
        uint lockedTokens = address(this).balance - totalSupply();
        require(_amount <= lockedTokens);

        // _mint will normalize _depositor
        _mint(_depositor, _amount);

        emit Deposit(msg.sender, msg.value);
    }
}