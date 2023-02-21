// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

library Signatures {
    bytes4 internal constant AUTHENTICATE_MESSAGE_METHOD = 0x9D8B0678;

    /**
     * @dev Attempts to validate a signature for a given signer and data hash.
     */
    function isValidSignature(
        address _signer, 
        bytes32 _hash, 
        bytes memory _signature
    ) internal view returns (bool) {
        // TODO
    }
}