// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "../utils/FilAddress.sol";

/**
 * @author fevmate (https://github.com/wadealexc/fevmate)
 * @notice Two-step owner transferrance mixin. Unlike many fevmate contracts,
 * no methods here normalize address inputs - so it is possible to transfer
 * ownership to an ID address. However, the acceptOwnership method enforces
 * that the pending owner address can actually be the msg.sender.
 *
 * This should mean it's possible for other Filecoin actor types to hold the
 * owner role - like BLS/SECP account actors.
 */
abstract contract OwnedClaimable {    
    
    using FilAddress for *;

    error Unauthorized();
    error InvalidAddress();

    /*//////////////////////////////////////
                  OWNER INFO
    //////////////////////////////////////*/

    address public owner;
    address pendingOwner;

    /*//////////////////////////////////////
                    EVENTS
    //////////////////////////////////////*/

    event OwnershipTransferred(address indexed oldOwner, address indexed newOwner);
    event OwnershipPending(address indexed currentOwner, address indexed pendingOwner);

    /*//////////////////////////////////////
                  CONSTRUCTOR
    //////////////////////////////////////*/

    constructor(address _owner) {
        if (_owner == address(0)) revert InvalidAddress();
        // normalize _owner to avoid setting an EVM actor's ID address as owner
        owner = _owner.normalize();

        emit OwnershipTransferred(address(0), owner);
    }

    /*//////////////////////////////////////
                OWNABLE METHODS
    //////////////////////////////////////*/

    modifier onlyOwner() virtual {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    /**
     * @notice Allows the current owner to revoke the owner role, locking
     * any onlyOwner functions.
     *
     * Note: this method requires that there is not currently a pending
     * owner. To revoke ownership while there is a pending owner, the
     * current owner must first set a new pending owner to address(0).
     * Alternatively, the pending owner can claim ownership and then
     * revoke it.
     */
    function revokeOwnership() public virtual onlyOwner {
        if (pendingOwner != address(0)) revert Unauthorized();
        owner = address(0);

        emit OwnershipTransferred(msg.sender, address(0));
    }

    /**
     * @notice Works like most 2-step ownership transfer methods. The current
     * owner can call this to set a new pending owner.
     * 
     * Note: the new owner address is NOT normalized - it is stored as-is.
     * This is safe, because the acceptOwnership method enforces that the
     * new owner can make a transaction as msg.sender.
     */
    function transferOwnership(address _newOwner) public virtual onlyOwner {
        pendingOwner = _newOwner;

        emit OwnershipPending(msg.sender, _newOwner);
    }

    /**
     * @notice Used by the pending owner to accept the ownership transfer.
     *
     * Note: If this fails unexpectedly, check that the pendingOwner is not
     * an ID address. The pending owner address should match the pending
     * owner's msg.sender address.         
     */
    function acceptOwnership() public virtual {
        if (msg.sender != pendingOwner) revert Unauthorized();

        // Transfer ownership and set pendingOwner to 0
        address oldOwner = owner;
        owner = msg.sender;
        delete pendingOwner;

        emit OwnershipTransferred(oldOwner, msg.sender);
    }
}
