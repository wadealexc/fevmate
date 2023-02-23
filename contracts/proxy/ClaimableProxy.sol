// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/utils/StorageSlot.sol";
import "../utils/FilAddress.sol";

/**
 * @notice ERC-1967 compliant proxy based on OpenZeppelin's TransparentUpgradeableProxy.
 * This contract is almost identical, except that it implements additional protection
 * for use in the FEVM:
 * - it implements a two-step role transferrance pattern for the proxy admin role
 * - it performs additional validation that the implementation contract is a valid
 *   target for the proxy. TODO details and impl (see notes below)
 * 
 * See https://docs.openzeppelin.com/contracts/4.x/api/proxy#TransparentUpgradeableProxy
 * for details on the TransparentUpgradableProxy and ProxyAdmin pattern.
 */
contract ClaimableProxy is ERC1967Proxy {

    using FilAddress for *;

    /*//////////////////////////////////////
                    STORAGE
    //////////////////////////////////////*/

    /**
     * @notice Storage slot with the pending proxy admin
     * 
     * This is bytes32(uint(keccak256("eip1967.proxy.pendingAdmin")) - 1), which
     * is validated in the constructor.
     */
    bytes32 internal constant PENDING_ADMIN_SLOT = 0x1f6bab18950bb488390c2f3d0a6c7185815b7c8f9c513a019b718697408a59d6;

    /*//////////////////////////////////////
                    EVENTS
    //////////////////////////////////////*/

    event AdminPending(address currentAdmin, address pendingAdmin);

    /*//////////////////////////////////////
                  CONSTRUCTOR
    //////////////////////////////////////*/

    constructor(
        address _logic, 
        address _admin, 
        bytes memory _data
    ) payable ERC1967Proxy(_logic, _data) {
        assert(PENDING_ADMIN_SLOT == bytes32(uint(keccak256("eip1967.proxy.pendingAdmin")) - 1));
        _changeAdmin(_admin.normalize());
    }

    /*//////////////////////////////////////
              PENDING ADMIN METHODS
    //////////////////////////////////////*/

    modifier ifPending() virtual {
        if (msg.sender == _getPendingAdmin()) {
            _;
        } else {
            _fallback();
        }
    }

    /**
     * @notice Used by the pending admin to accept the admin role.
     *
     * This will emit the AdminChanged event.
     */
    function acceptAdmin() external virtual payable ifPending {
        require(msg.value == 0);

        // Transfer the admin role and set pending admin to 0
        address newAdmin = StorageSlot.getAddressSlot(PENDING_ADMIN_SLOT).value;
        _changeAdmin(newAdmin);
        _setPendingAdmin(address(0));
    }

    /*//////////////////////////////////////
                 ADMIN METHODS
    //////////////////////////////////////*/

    modifier ifAdmin() virtual {
        if (msg.sender == _getAdmin()) {
            _;
        } else {
            _fallback();
        }
    }

    /**
     * @notice When called by the current admin, this updates the proxy's
     * pending admin.
     *
     * Note: the new admin address is NOT normalized - it is stored as-is.
     * This means the pending admin can be set to an ID address. This should
     * be safe, because the acceptAdmin method enforces that the new admin
     * can make a transaction as msg.sender.
     */
    function changeAdmin(address _newAdmin) external virtual payable ifAdmin {
        require(msg.value == 0);

        _setPendingAdmin(_newAdmin);
    }

    /**
     * @notice Upgrade the proxy to a new implementation.
     *
     * TODO:
     * Under the hood, this performs an extcodesize check to ensure the new
     * implementation is a contract. However, native actors will return with
     * an extcodesize check of 1, and would pass through addr.normalize().
     *
     * How should this be handled?
     * - We could use mustNormalize(), which reverts if the address cannot
     *   be converted to an Eth address. However, this may be restrictive
     *   down the line.
     * - We could additionally check that extcodehash does not return the
     *   empty hash currently returned by native actors.
     * - Finally, we could use handle_native_method and ask the implementation
     *   for a magic value that shows "yes, I can be an implementation contract"
     */
    function upgradeTo(address _newImplementation) external virtual payable ifAdmin {
        _requireZeroValue();
        _upgradeToAndCall(_newImplementation.normalize(), bytes(""), false);
    }

    function upgradeToAndCall(
        address _newImplementation, 
        bytes calldata _data
    ) external virtual payable ifAdmin {
        _upgradeToAndCall(_newImplementation.normalize(), _data, true);
    }

    /*//////////////////////////////////////
                 ADMIN GETTERS
    //////////////////////////////////////*/

    /**
     * @notice Returns the proxy's admin address
     */
    function admin() external payable ifAdmin returns (address) {
        _requireZeroValue();
        return _getAdmin();
    }

    /**
     * @notice Returns the proxy's pending admin address
     */
    function pendingAdmin() external payable ifAdmin returns (address) {
        _requireZeroValue();
        return _getPendingAdmin();
    }

    /**
     * @notice Returns the proxy's implementation address
     */
    function implementation() external payable ifAdmin returns (address) {
        _requireZeroValue();
        return _implementation();
    }

    /*//////////////////////////////////////
                INTERNAL METHODS
    //////////////////////////////////////*/

    function _setPendingAdmin(address _newAdmin) internal virtual {
        StorageSlot.getAddressSlot(PENDING_ADMIN_SLOT).value = _newAdmin;

        emit AdminPending(_getAdmin(), _newAdmin);
    }

    function _getPendingAdmin() internal virtual returns (address) {
        return StorageSlot.getAddressSlot(PENDING_ADMIN_SLOT).value;
    }

    function _beforeFallback() internal virtual override {
        require(msg.sender != _getAdmin() && msg.sender != _getPendingAdmin());
        super._beforeFallback();
    }

    function _requireZeroValue() internal {
        require(msg.value == 0);
    }
}