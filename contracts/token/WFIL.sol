// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./ERC20.sol";
import "../utils/FilAddress.sol";
import "../access/OwnedClaimable.sol";

/**
 * @author fevmate (https://github.com/wadealexc/fevmate)
 * @notice Wrapped filecoin implementation, using ERC20-FEVM mixin.
 */
contract WFIL is ERC20("Wrapped FIL", "WFIL", 18), OwnedClaimable {

    using FilAddress for *;

    error TimelockActive();

    /*//////////////////////////////////////
                 WFIL STORAGE
    //////////////////////////////////////*/

    // Timelock for 6 months after contract is deployed
    // Applies only to recoverDeposit. See comments there for info
    uint public immutable recoveryTimelock = block.timestamp + 24 weeks;

    /*//////////////////////////////////////
                    EVENTS
    //////////////////////////////////////*/

    event Deposit(address indexed from, uint amount);
    event Withdrawal(address indexed to, uint amount);
    
    /*//////////////////////////////////////
                  CONSTRUCTOR
    //////////////////////////////////////*/
    
    constructor(address _owner) OwnedClaimable(_owner) {}

    /*//////////////////////////////////////
                  WFIL METHODS
    //////////////////////////////////////*/

    /**
     * @notice Fallback function - Fil transfers via standard address.call
     * will end up here and trigger the deposit function, minting the caller
     * with WFIL 1:1.
     *
     * Note that transfers of value via the FVM's METHOD_SEND bypass bytecode,
     * and will not credit the sender with WFIL in return. Please ensure you
     * do NOT send the contract Fil via METHOD_SEND - always use InvokeEVM.
     *
     * For more information on METHOD_SEND, see recoverDeposit below.
     */
    receive() external payable virtual {
        deposit();
    }

    /**
     * @notice Deposit Fil into the contract, and mint WFIL 1:1.
     */
    function deposit() public payable virtual {
        _mint(msg.sender, msg.value);

        emit Deposit(msg.sender, msg.value);
    }

    /**
     * @notice Burns _amount WFIL from caller's balance, and transfers them
     * the unwrapped Fil 1:1.
     *
     * Note: The fund transfer used here is address.call{value: _amount}(""),
     * which does NOT work with the FVM's builtin Multisig actor. This is
     * because, under the hood, address.call acts like a message to an actor's
     * InvokeEVM method. The Multisig actor does not implement this method.
     * 
     * This is a known issue, but we've decided to keep the method as-is,
     * because it's likely that the Multisig actor is eventually upgraded to
     * support this method. Even though a Multisig actor cannot directly
     * withdraw, it is still possible for Multisigs to deposit, transfer,
     * etc WFIL. So, if your Multisig actor needs to withdraw, you can
     * transfer your WFIL to another contract, which can perform the
     * withdrawal for you.
     *
     * (Though Multisig actors are not supported, BLS/SECPK/EthAccounts
     * and EVM contracts can use this method normally)
     */
    function withdraw(uint _amount) public virtual {
        _burn(msg.sender, _amount);

        emit Withdrawal(msg.sender, _amount);

        payable(msg.sender).sendValue(_amount);
    }

    /**
     * @notice Used by owner to unstick Fil that was directly transferred
     * to the contract without triggering the deposit/receive functions.
     * When called, _amount stuck Fil is converted to WFIL on behalf of
     * the passed-in _depositor.
     *
     * This method ONLY converts Fil that would otherwise be permanently
     * lost.
     *
     * --- About ---
     *
     * In the event someone accidentally sends Fil to this contract via
     * FVM method METHOD_SEND (or via selfdestruct), the Fil will be
     * lost rather than being converted to WFIL. This is because METHOD_SEND 
     * transfers value without invoking the recipient's code.
     *
     * If this occurs, the contract's Fil balance will go up, but no WFIL
     * will be minted. Luckily, this means we can calculate the number of  
     * stuck tokens as the contract's Fil balance minus WFIL totalSupply, 
     * and ensure we're only touching stuck tokens with this method.
     *
     * Please ensure you only ever send funds to this contract using the
     * FVM method InvokeEVM! This method is not a get-out-of-jail free card,
     * and comes with no guarantees.
     *
     * (If you're a lost EVM dev, address.call uses InvokeEVM under the
     * hood. So in a purely contract-contract context, you don't need
     * to do anything special - use address.call, or call the WFIL.deposit
     * method as you would normally.)
     */
    function recoverDeposit(address _depositor, uint _amount) public virtual onlyOwner {
        // This method is locked for 6 months after contract deployment.
        // This is to give the deployers time to sort out the best/most
        // equitable way to recover and distribute accidentally-locked
        // tokens.
        if (block.timestamp < recoveryTimelock) revert TimelockActive();

        // Calculate number of locked tokens
        uint lockedTokens = address(this).balance - totalSupply;
        require(_amount <= lockedTokens);

        // Normalize depositor. _mint also does this, but we want to
        // emit the normalized address in the Deposit event below.
        _depositor = _depositor.normalize();

        _mint(_depositor, _amount);
        emit Deposit(_depositor, _amount);
    }
}
