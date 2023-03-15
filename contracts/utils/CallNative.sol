// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./FilAddress.sol";

library CallNative {

    // keccak([])
    bytes32 constant EVM_EMPTY_CODEHASH = 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470;
    // keccak([0xFE])
    bytes32 constant FIL_NATIVE_CODEHASH = 0xbcc90f2d6dada5b18e155c17a1c0a55920aae94f39857d39d0d8ed07ae8f228b;

    uint64 constant MAX_RESERVED_METHOD = 1023;
    bytes4 constant NATIVE_METHOD_SELECTOR = 0x868e10c4;

    uint64 constant DEFAULT_FLAG = 0x00000000;
    uint64 constant READONLY_FLAG = 0x00000001;

    function callActor(
        uint64 _id, 
        uint64 _method, 
        uint _value, 
        uint64 _codec, 
        bytes memory _data
    ) internal returns (bool, bytes memory) {
        return callHelper(false, _id, _method, _value, _codec, _data);
    }

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