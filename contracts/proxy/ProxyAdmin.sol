// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./ClaimableProxy.sol";
import "../access/Ownable.sol";

/**
 * @notice Auxiliary contract meant to be assigned as admin of a ClaimableProxy.
 * This is almost identical to OpenZeppelin's ProxyAdmin, except that it implements
 * a two-step role transferrance pattern as this is safer and more likely to be
 * forwards-compatible in the FEVM.
 *
 * See https://docs.openzeppelin.com/contracts/4.x/api/proxy#TransparentUpgradeableProxy
 * for details on the TransparentUpgradableProxy and ProxyAdmin pattern.
 */
contract ProxyAdmin is Ownable {

    /**
     * @notice Returns the implementation address of the proxy
     */
    function getProxyImplementation(address _proxy) public virtual view returns (address) {
        // We need to manually run the static call since the getter cannot be flagged as view
        // bytes4(keccak256("implementation()")) == 0x5c60da1b
        (bool success, bytes memory returndata) = _proxy.staticcall(hex"5c60da1b");
        require(success);
        return abi.decode(returndata, (address));
    }

    /**
     * @notice Returns the admin address of the proxy
     * 
     * Note that this only functions if this contract is the admin, or if the
     * implementation contract has an "admin()" function that can be called by
     * this contract.
     */
    function getProxyAdmin(address _proxy) public virtual view returns (address) {
        // We need to manually run the static call since the getter cannot be flagged as view
        // bytes4(keccak256("admin()")) == 0xf851a440
        (bool success, bytes memory returndata) = _proxy.staticcall(hex"f851a440");
        require(success);
        return abi.decode(returndata, (address));
    }

    /**
     * @notice Returns the pending admin address of the proxy
     *
     * Note that this only functions if this contract is the admin, or if the
     * implementation contract has a "pendingAdmin()" function that can be called
     * by this contract.
     */
    function getProxyPendingAdmin(address _proxy) public virtual view returns (address) {
        // We need to manually run the static call since the getter cannot be flagged as view
        // bytes4(keccak256("pendingAdmin()")) == 0x26782247
        (bool success, bytes memory returndata) = _proxy.staticcall(hex"26782247");
        require(success);
        return abi.decode(returndata, (address));
    }

    /**
     * @notice Update the proxy's pending admin address to a new address. The new
     * admin address must call proxy.acceptAdmin() to finalize the change.
     *
     * Note: we do not perform address normalization. Instead, we're using the
     * 2-step role transferrance pattern to ensure the new admin can successfully
     * claim the role.
     */
    function changeProxyAdmin(address _proxy, address _newAdmin) public virtual onlyOwner {
        ClaimableProxy(_proxy).changeAdmin(_newAdmin);
    }

    /**
     * @notice Accept the proxy's admin role. This contract must be the proxy's
     * pending admin.
     */
    function acceptProxyAdmin(address _proxy) public virtual onlyOwner {
        ClaimableProxy(_proxy).acceptAdmin();
    }

    /**
     * @notice Upgrade proxy to a new implementation.
     *
     * TODO see notes in ClaimableProxy - need to figure out how to
     * handle normalization here.
     */
    function upgrade(address _proxy, address _implementation) public virtual onlyOwner {
        _implementation = _implementation.mustNormalize();
        ClaimableProxy(_proxy).upgradeTo(_implementation);
    }

    /**
     * @notice Upgrade proxy to a new implementation, then call a method on the proxy,
     * supplying some calldata. This can be used to initialize a new version.
     */
    function upgradeAndCall(
        address _proxy, 
        address _implementation, 
        bytes calldata _data
    ) public payable virtual onlyOwner {
        _implementation = _implementation.mustNormalize();
        ClaimableProxy(_proxy).upgradeToAndCall{value: msg.value}(_implementation, _data);
    }
}