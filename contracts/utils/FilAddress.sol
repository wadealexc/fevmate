// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {
    DelegatedAddrNotFound,
    InsufficientBalance,
    DelegatedAddrNotFound
} from "./Errors.sol";

/**
 * @author fevmate (https://github.com/wadealexc/fevmate)
 * @notice Utility functions for converting between id and
 * eth addresses. Helps implement address normalization.
 *
 * See README for more details about how to use this when
 * developing for the FEVM.
 */
library FilAddress {

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
    // address constant GET_ACTOR_TYPE = 0xFe00000000000000000000000000000000000004; // (deprecated)
    address constant CALL_ACTOR_BY_ID = 0xfe00000000000000000000000000000000000005;

    // bytes20 constant NULL = 0x0000000000000000000000000000000000000000;
    // bytes22 constant F4_ADDR_EXAMPLE = 0x040Aff00000000000000000000000000000000000001;

    // Min/Max ID address values - useful for bitwise operations
    address constant MAX_ID_MASK = 0x000000000000000000000000fFFFFFffFFFFfffF;
    address constant MAX_ADDRESS_MASK = 0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF;
    address constant ZERO_ID_ADDRESS = 0xfF00000000000000000000000000000000000000;
    address constant MAX_ID_ADDRESS = 0xFf0000000000000000000000FFfFFFFfFfFffFfF;

    /**
     * @notice Convert ID to Eth address
     *
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
     * @notice Convert ID to Eth address
     *
     * Attempt to convert address _a from an ID address to an Eth address
     * If _a is NOT an ID address, this returns _a unchanged
     * If _a does NOT have a corresponding Eth address, this method reverts
     *
     * This method can be used when you want a guarantee that an ID address is not
     * returned. Note, though, that rejecting ID addresses may mean you don't support
     * other Filecoin-native actors.
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
        if (!success) revert DelegatedAddrNotFound();

        return eth;
    }

    /**
     * @notice Checks whether _a matches the ID address format:
     * [0xFF] [bytes11(0)] [uint64(id)]
     *
     * If _a matches, returns true and the id
     */
    function isIDAddress(address _a) internal pure returns (bool isID, uint64 id) {
        /// @solidity memory-safe-assembly
        assembly {
            // Get the last 8 bytes of _a - this is the id
            let temp := and(_a, MAX_ID_MASK)

            // Zero out the last 8 bytes of _a and compare to the zero id address
            let a_mask := and(_a, not(temp))
            if eq(a_mask, ZERO_ID_ADDRESS) {
                isID := true
                id := temp
            }
        }
    }

    /**
     * @notice Given an Actor ID, converts it to an EVM-compatible address.
     * If _id has a corresponding Eth address, we return that
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
     * @notice Given an Actor ID, converts it to a 20-byte ID address
     *
     * Note that this method does NOT check if the _id has a corresponding
     * Eth address. If you want that, try toAddress above.
     */
    function toIDAddress(uint64 _id) internal pure returns (address addr) {
        /// @solidity memory-safe-assembly
        assembly { addr := or(ZERO_ID_ADDRESS, _id) }
    }

    /**
     * @notice Query the lookup_delegated_address precompile to convert an actor id
     * to an Eth address.
     *
     * --- About ---
     *
     * The lookup_delegated_address precompile retrieves the actor state corresponding
     * to the id. If the actor has a delegated address, it is returned using fil
     * address encoding (see below).
     *
     * f4, or delegated addresses, have a namespace as well as a subaddress that can
     * be up to 54 bytes long. This is to support future address formats. Currently,
     * though, the f4 format is only used to support Eth addresses.
     *
     * Consequently, the only addresses lookup_delegated_address should return have:
     * - Prefix:     "f4" address      - 1 byte   - (0x04)
     * - Namespace:  EAM actor id      - 1 byte   - (0x0A)
     * - Subaddress: EVM-style address - 20 bytes - (EVM address)
     *
     * This method checks that the precompile output exactly matches this format. If
     * we get anything else, we return (false, 0x00).
     */
    function getEthAddress(uint64 _id) internal view returns (bool success, address eth) {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0, _id)
            // LOOKUP_DELEGATED_ADDRESS returns an f4-encoded address. For
            // Eth addresses, the format is a 20-byte address, prefixed with
            // 0x040A.
            //
            // So, we're expecting 22 bytes of returndata
            success := staticcall(gas(), LOOKUP_DELEGATED_ADDRESS, 0, 0x20, 0x20, 22)
            let result := mload(0x20)
            // Result is left-aligned - shift right and remove prefix bytes
            eth := and(MAX_ADDRESS_MASK, shr(80, result))

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
     * @notice Eth address -> actor id
     *
     * Given an Eth address, queries the RESOLVE_ADDRESS precompile to look
     * up the corresponding actor id.
     *
     * If there is no ID address, this returns (false, 0)
     * If the passed-in address is already an ID address, returns (true, id)
     */
    function getActorID(address _eth) internal view returns (bool success, uint64 id) {
        // First, check if we already have an ID address
        (success, id) = isIDAddress(_eth);
        if (success) {
            return (success, id);
        }

        /// @solidity memory-safe-assembly
        assembly {
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

    /**
     * @notice Replacement for Solidity's address.send and address.transfer
     * This sends _amount to _recipient, forwarding all available gas and
     * reverting if there are any errors.
     *
     * If _recpient is an Eth address, this works the way you'd
     * expect the EVM to work.
     *
     * If _recpient is an ID address, this works if:
     * 1. The ID corresponds to an Eth EOA address      (EthAccount actor)
     * 2. The ID corresponds to an Eth contract address (EVM actor)
     * 3. The ID corresponds to a BLS/SECPK address     (Account actor)
     *
     * If _recpient is some other Filecoin-native actor, this will revert.
     */
    function sendValue(address payable _recipient, uint _amount) internal {
        if (address(this).balance < _amount) revert InsufficientBalance();

        (bool success, ) = _recipient.call{value: _amount}("");
        if (!success) revert UnsafeReceiver();
    }

    function returnDataSize() private pure returns (uint size) {
        /// @solidity memory-safe-assembly
        assembly { size := returndatasize() }
    }
}
