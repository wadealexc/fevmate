// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ERC20} from "./ERC20.sol";
import {FilAddress} from "../utils/FilAddress.sol";

/**
 * @author fevmate (https://github.com/wadealexc/fevmate)
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

    function withdraw(uint _amount) public virtual {
        _burn(msg.sender, _amount);

        emit Withdrawal(msg.sender, _amount);

        payable(msg.sender).sendValue(_amount);
    }

    receive() external payable virtual {
        deposit();
    }
}
