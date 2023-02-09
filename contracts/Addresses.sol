// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

library Addresses {

    // Builtin Actor addresses
    address constant SYSTEM_ACTOR = 0xfF00000000000000000000000000000000000000;
    address constant INIT_ACTOR = 0xff00000000000000000000000000000000000001;
    address constant REWARD_ACTOR = 0xff00000000000000000000000000000000000002;
    address constant CRON_ACTOR = 0xFF00000000000000000000000000000000000003;
    address constant POWER_ACTOR = 0xFf00000000000000000000000000000000000004;
    address constant MARKET_ACTOR = 0xff00000000000000000000000000000000000005;
    address constant VERIFIED_REGISTRY_ACTOR = 0xFF00000000000000000000000000000000000006;
    address constant DATACAP_TOKEN_ACTOR = 0xfF00000000000000000000000000000000000007;
    address constant EAM_ACTOR = 0xfF0000000000000000000000000000000000000a;
    // address constant CHAOS_ACTOR = 0xFF00000000000000000000000000000000000000; // 98
    // address constant BURNT_FUNDS_ACTOR = 0xFF00000000000000000000000000000000000000; // 99

    // Precompile addresses
    address constant RESOLVE_ADDRESS = 0xFE00000000000000000000000000000000000001;
    address constant LOOKUP_DELEGATED_ADDRESS = 0xfE00000000000000000000000000000000000002;
    address constant CALL_ACTOR = 0xfe00000000000000000000000000000000000003;
    // address constant GET_ACTOR_TYPE = 0xFe00000000000000000000000000000000000004;
    address constant CALL_ACTOR_BY_ID = 0xfe00000000000000000000000000000000000005;

    // bytes20 constant NULL = 0x0000000000000000000000000000000000000000;
    // bytes22 constant F4_ADDR_EXAMPLE = 0x040Aff00000000000000000000000000000000000001;    

    /**
     * Attempt to convert address _a from an ID address to an Eth address
     * If _a is NOT an ID address, this returns _a
     * If _a does NOT have a corresponding Eth address, this returns _a
     * 
     * NOTE: It is possible this returns an ID address! If you want a method
     *       that will NEVER return an ID address, see mustNormalize below.
     */
    function normalize(address _a) internal view returns (address) {
        // First, check if we have an ID address. If we don't, return as-is
        (bool isID, uint64 id) = isIDAddress(_a);
        if (!isID) {
            return _a;
        }

        // We have an ID address -- attempt the conversion
        // If there is no corresponding Eth address, return _a
        (bool success, address eth) = getEthAddress(id);
        if (!success) {
            return _a;
        } else {
            return eth;
        }
    }

    /**
     * Attempt to convert address _a from an ID address to an Eth address
     * If _a is NOT an ID address, this returns _a unchanged
     * If _a does NOT have a corresponding Eth address, this method reverts
     */
    function mustNormalize(address _a) internal view returns (address) {
        // First, check if we have an ID address. If we don't, return as-is
        (bool isID, uint64 id) = isIDAddress(_a);
        if (!isID) {
            return _a;
        }

        // We have an ID address -- attempt the conversion
        // If there is no corresponding Eth address, revert
        (bool success, address eth) = getEthAddress(id);
        require(success, "No corresponding Eth address");
        return eth;
    }

    /**
     * Checks whether _a matches the ID address format:
     * [0xFF] [bytes11(0)] [uint64(id)]
     *
     * If _a matches, returns true and the id
     */
    function isIDAddress(address _a) internal pure returns (bool isID, uint64 id) {
        uint64 ID_MASK = type(uint64).max;
        assembly ("memory-safe") {
            // Get the last 8 bytes of _a - this is the id
            let temp := and(_a, ID_MASK)

            // Zero out the last 8 bytes of _a and compare to the system actor
            //
            // The system actor is an ID address where id == 0, so if _a is an
            // ID address, these will be equal.
            let a_mask := and(_a, not(temp))
            if eq(a_mask, SYSTEM_ACTOR) {
                isID := true
                id := temp
            }
        }
    }

    /**
     * Given an Actor ID, converts it to an EVM-compatible address.
     * 
     * If _id can be converted to an Eth address, return that
     * Otherwise, _id is returned as a 20-byte ID address
     */
    function toAddress(uint64 _id) internal view returns (address) {
        (bool success, address eth) = getEthAddress(_id);
        if (success) {
            return eth;
        } else {
            return toIDAddress(_id);
        }
    }

    /**
     * Given an Actor ID, converts it to an EVM-compatible ID address. See
     * isIDAddress above for definition.
     */
    function toIDAddress(uint64 _id) internal pure returns (address addr) {
        assembly ("memory-safe") { addr := or(SYSTEM_ACTOR, _id) }
    }

    /**
     * Given an Actor ID, queries the LOOKUP_DELEGATED_ADDRESS precompile to
     * to try to convert it to an Eth address. 
     * 
     * If _id cannot be converted to an Eth address, this returns (false, 0x00)
     */
    function getEthAddress(uint64 _id) internal view returns (bool success, address eth) {
        uint160 mask = type(uint160).max;
        assembly ("memory-safe") {
            mstore(0, _id)
            // LOOKUP_DELEGATED_ADDRESS returns an f4-encoded address. For
            // Eth addresses, the format is a 20-byte address, prefixed with
            // 0x040A.
            //
            // So, we're expecting 22 bytes of returndata
            success := staticcall(gas(), LOOKUP_DELEGATED_ADDRESS, 0, 0x20, 0x20, 22)
            let result := mload(0x20)
            // Result is left-aligned - shift right and remove prefix bytes
            eth := and(mask, shr(80, result))

            // Sanity-check f4 prefix - should be 0x040A
            // If it's not, we didn't get an Eth address!
            let prefix := shr(240, result)
            if iszero(eq(prefix, 0x040A)) {
                success := false
                eth := 0
            }
        }
        if (!success || returnDataSize() != 22) {
            return (false, address(0));
        }
    }

    /**
     * Given an Eth address, queries the RESOLVE_ADDRESS precompile to look
     * up the corresponding ID address.
     * 
     * If there is no ID address, this returns (false, 0)
     * If the passed-in address is already an ID address, returns (true, id)
     */
    function getActorID(address _eth) internal view returns (bool success, uint64 id) {
        // First, check if we already have an ID address
        (success, id) = isIDAddress(_eth);
        if (success) {
            return(success, id);
        }

        assembly ("memory-safe") {
            // Convert EVM address to f4-encoded format.
            // This means 22 bytes, with prefix 0x040A:
            // * 0x04 is the protocol - "f4" address
            // * 0x0A is the namespace - "10" for the EAM actor
            _eth := or(
                shl(240, 0x040A),
                shl(80, _eth)
            )
            mstore(0, _eth)
            // Call RESOLVE_ADDRESS. If successful, the result will be our id
            success := staticcall(gas(), RESOLVE_ADDRESS, 0, 22, 0, 0x20)
            id := mload(0)
        }
        if (!success || returnDataSize() != 32) {
            return (false, 0);
        }
    }

    function returnDataSize() private pure returns (uint size) {
        assembly ("memory-safe") { size := returndatasize() }
    }
}