// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

abstract contract BaseUpgradable {

    // frc42_dispatch::method_hash!("IsValidProxyTarget") = 3945216846
    // frc42_dispatch::method_hash!("IsValidProxyTarget") = 0x00000000EB273B4E
    // function IsValidProxyTarget() -> (uint64)
    uint64 internal constant IS_VALID_PROXY_TARGET_METHOD = uint64(bytes8(0x00000000EB273B4E));

    uint32 internal constant EXIT_SUCCESS = 0;
    uint64 internal constant CBOR_CODEC = 81;


    function handle_filecoin_method(
        uint64 _method, 
        uint64, 
        bytes calldata
    ) public virtual payable returns (uint32, uint64, bytes memory) {
        if (_method == IS_VALID_PROXY_TARGET_METHOD) {
            return (
                EXIT_SUCCESS,
                CBOR_CODEC,
                hex"00000000EB273B4E" // Use method number as "magic value" to return
            );
        }

        revert("unsupported method"); // TODO or return default values?
    }
}