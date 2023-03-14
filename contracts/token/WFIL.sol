// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./ERC20.sol";
import "../utils/FilAddress.sol";

/**
 * @author fevmate
 * @notice Wrapped Filecoin implementation, using ERC20-FEVM mixin.
 */
contract WFIL is ERC20("Wrapped Filecoin", "WFIL", 18) {

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

    /**
     * @notice Burn _amount from sender's balance, and send unwrapped
     * Fil to sender.
     *
     * If msg.sender is an Eth address, we transfer funds normally
     * using sendValue - address.call{value: _amount}("")
     *
     * If msg.sender is an ID address, we know they are a non-EVM
     * actor. In this case, we transfer Fil using sendNoExec, which
     * uses a FEVM precompile to transfer Fil without executing the
     * recipient's code.
     *
     * We do this because address.call requires the recipient to
     * handle the FVM-side InvokeEVM method. Currently, BLS/SECPK
     * actors handle this via a fallback, but the Multisig actor
     * does not. All actors can receive funds via METHOD_SEND, though,
     * so we can support multisigs explicitly like this.
     */
    function withdraw(uint _amount) public virtual {
        _burn(msg.sender, _amount);

        emit Withdrawal(msg.sender, _amount);

        if (msg.sender.isIDAddress()) {
            payable(msg.sender).sendNoExec(_amount);
        } else {
            payable(msg.sender).sendValue(_amount);
        }
    }

    receive() external payable virtual {
        deposit();
    }
}