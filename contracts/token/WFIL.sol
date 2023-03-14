// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ERC20} from "./ERC20.sol";
import {FilAddress} from "../utils/FilAddress.sol";
import {OwnedClaimable} from "../access/OwnedClaimable.sol";

/**
 * @author fevmate (https://github.com/wadealexc/fevmate)
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

    receive() external payable virtual {
        deposit();
    }

    function deposit() public payable virtual {
        _mint(msg.sender, msg.value);

        emit Deposit(msg.sender, msg.value);
    }

    function withdraw(uint _amount) public virtual {
        _burn(msg.sender, _amount);

        emit Withdrawal(msg.sender, _amount);

        payable(msg.sender).sendValue(_amount);
    }

    /**
     * @notice Used by owner to unstick Fil that was directly transferred
     * to the contract without triggering the deposit/receive functions.
     *
     * This is possible in the event someone accidentally sends Fil via
     * FVM method METHOD_SEND (or via selfdestruct) - as neither of these
     * will trigger the contract's bytecode.
     *
     * If this occurs, the contract's balance will go up, but no tokens
     * will be minted.
     *
     * This means we can calculate the number of locked tokens as the
     * contract's Fil balance minus the token supply, and ensure we're
     * only touching locked tokens with this method.
     */
    function recoverDeposit(address _depositor, uint _amount) public virtual onlyOwner {
        // Calculate number of locked tokens
        // Note: we could extend this by also factoring balanceOf[address(this)]
        // which would also catch WFIL sent to the contract itself.
        uint lockedTokens = address(this).balance - totalSupply;
        require(_amount <= lockedTokens);

        // Normalize depositor. _mint also does this, but we want to
        // emit the normalized address in the Deposit event below.
        _depositor = _depositor.normalize();

        _mint(_depositor, _amount);
        emit Deposit(_depositor, _amount);
    }
}
