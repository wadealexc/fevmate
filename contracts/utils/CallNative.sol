// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./FilAddress.sol";

/**
 * @author fevmate (https://github.com/wadealexc/fevmate)
 * @notice Helpers for calling actors by ID
 */
library CallNative {

    // keccak([])
    bytes32 constant EVM_EMPTY_CODEHASH = 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470;
    // keccak([0xFE])
    bytes32 constant FIL_NATIVE_CODEHASH = 0xbcc90f2d6dada5b18e155c17a1c0a55920aae94f39857d39d0d8ed07ae8f228b;

    uint64 constant MAX_RESERVED_METHOD = 1023;
    bytes4 constant NATIVE_METHOD_SELECTOR = 0x868e10c4;

    uint64 constant DEFAULT_FLAG = 0x00000000;
    uint64 constant READONLY_FLAG = 0x00000001;

    /**
     * @notice Call actor by ID. This method allows the target actor
     * to change state. If you don't want this, see the readonly 
     * method below.
     */
    function callActor(
        uint64 _id, 
        uint64 _method, 
        uint _value, 
        uint64 _codec, 
        bytes memory _data
    ) internal returns (bool, bytes memory) {
        return callHelper(false, _id, _method, _value, _codec, _data);
    }

    /**
     * @notice Call actor by ID, and revert if state changes occur.
     * This is the call_actor_id precompile equivalent of an EVM
     * staticcall. By passing the READONLY flag, the FVM will prevent
     * state changes in the same way staticcall does.
     *
     * Note: The assembly here is because the call_actor_id precompile
     * has to be called using delegatecall, and solc's mutability checker
     * won't allow me to call this method "view" if it can delegatecall.
     * 
     * Having a "view" method is nice for usability, though, because users
     * can "read" contract methods in frontends without sending a transaction.
     * 
     * ... so we trick solc into allowing the method to be marked as view.
     */
    function callActorReadonly(
        uint64 _id,
        uint64 _method,
        uint64 _codec,
        bytes memory _data
    ) internal view returns (bool, bytes memory) {
        function(bool, uint64, uint64, uint, uint64, bytes memory) internal view returns (bool, bytes memory) callFn;
        function(bool, uint64, uint64, uint, uint64, bytes memory) internal returns (bool, bytes memory) helper = callHelper;
        assembly { callFn := helper }
        return callFn(true, _id, _method, 0, _codec, _data);
    }

    function callHelper(
        bool _readonly,
        uint64 _id, 
        uint64 _method, 
        uint _value, 
        uint64 _codec, 
        bytes memory _data
    ) private returns (bool, bytes memory) {
        uint64 flags = _readonly ? READONLY_FLAG : DEFAULT_FLAG;
        require(!_readonly || _value == 0); // sanity check - shouldn't hit this in a private method
        bytes memory input = abi.encode(_method, _value, flags, _codec, _data, _id);
        return FilAddress.CALL_ACTOR_BY_ID.delegatecall(input);
    }
}