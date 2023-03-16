// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "../../utils/FilAddress.sol";
import "./IERC721TokenReceiver.sol";

/**
 * @author fevmate (https://github.com/wadealexc/fevmate)
 * @notice ERC721 mixin for the FEVM. This contract implements the ERC721
 * standard, with additional safety features for the FEVM.
 *
 * All methods attempt to normalize address input. This means that if
 * they are provided ID addresses as input, they will attempt to convert
 * these addresses to standard Eth addresses. 
 * 
 * This is an important consideration when developing on the FEVM, and
 * you can read about it more in the README.
 */
abstract contract ERC721 {
    
    using FilAddress for *;
    
    error Unauthorized();
    error UnsafeReceiver();
    error NullOwner();

    /*//////////////////////////////////////
                  TOKEN INFO
    //////////////////////////////////////*/

    string public name;
    string public symbol;
    
    /*//////////////////////////////////////
                ERC-721 STORAGE
    //////////////////////////////////////*/

    // Maps tokenId to owner address
    mapping(uint => address) tokenOwners;
    // Maps owner address to token count
    mapping(address => uint) ownerBalances;

    // Maps tokenId to approved address
    mapping(uint => address) tokenApprovals;
    // Maps owner address to operator approvals
    mapping(address => mapping(address => bool)) operatorApprovals;

    /*//////////////////////////////////////
                    EVENTS
    //////////////////////////////////////*/

    event Transfer(address indexed from, address indexed to, uint indexed tokenId);
    event Approval(address indexed owner, address indexed spender, uint indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed spender, bool isApproved);

    /*//////////////////////////////////////
                  CONSTRUCTOR
    //////////////////////////////////////*/

    constructor(
        string memory _name,
        string memory _symbol
    ) {
        name = _name;
        symbol = _symbol;
    }

    /*//////////////////////////////////////
                ERC-721 METHODS
    //////////////////////////////////////*/

    function transferFrom(address _owner, address _to, uint _tokenId) public virtual {
        // Attempt to convert owner and destination to Eth addresses
        _owner = _owner.normalize();
        _to = _to.normalize();

        // Ensure the _owner is the owner of _tokenId, and
        // Ensure msg.sender is allowed to transfer _tokenId
        if (
            _owner != ownerOf(_tokenId) ||
            (
                msg.sender != _owner &&
                !isApprovedForAll(_owner, msg.sender) &&
                msg.sender != getApproved(_tokenId)
            )
        ) revert Unauthorized();

        if (_to == address(0)) revert UnsafeReceiver();

        unchecked {
            ownerBalances[_owner]--;
            ownerBalances[_to]++;
        }

        tokenOwners[_tokenId] = _to;
        delete tokenApprovals[_tokenId];

        emit Transfer(_owner, _to, _tokenId);
    }

    function safeTransferFrom(address _owner, address _to, uint _tokenId) public virtual {
        // transferFrom will normalize input
        transferFrom(_owner, _to, _tokenId);

        // Check receiver. Only _owner needs to be normalized here, since:
        // - msg.sender is already normalized by default
        // - _to is getting called, which behaves identically for ID / Eth addresses
        _checkSafeReceiver(_to, msg.sender, _owner.normalize(), _tokenId, "");
    }

    function safeTransferFrom(address _owner, address _to, uint _tokenId, bytes calldata _data) public virtual {
        // transferFrom will normalize input
        transferFrom(_owner, _to, _tokenId);

        // Check receiver. Only _owner needs to be normalized here, since:
        // - msg.sender is already normalized by default
        // - _to is getting called, which behaves identically for ID / Eth addresses
        _checkSafeReceiver(_to, msg.sender, _owner.normalize(), _tokenId, _data);
    }

    function approve(address _spender, uint _tokenId) public virtual {
        // Attempt to convert spender to Eth address
        _spender = _spender.normalize();

        // No need to normalize, since we're reading from storage
        // and we only store normalized addresses
        address owner = ownerOf(_tokenId);
        if (msg.sender != owner && !isApprovedForAll(owner, msg.sender)) revert Unauthorized();

        tokenApprovals[_tokenId] = _spender;
        emit Approval(owner, _spender, _tokenId);
    }

    function setApprovalForAll(address _operator, bool _isApproved) public virtual {
        // Attempt to convert operator to Eth address
        _operator = _operator.normalize();

        operatorApprovals[msg.sender][_operator] = _isApproved;

        emit ApprovalForAll(msg.sender, _operator, _isApproved);
    }

    /*//////////////////////////////////////
                ERC-721 GETTERS
    //////////////////////////////////////*/

    function tokenURI(uint _tokenId) public virtual view returns (string memory);

    function balanceOf(address _owner) public virtual view returns (uint) {
        // Attempt to convert owner to Eth address
        _owner = _owner.normalize();

        if (_owner == address(0)) revert NullOwner();

        return ownerBalances[_owner];
    }

    function ownerOf(uint _tokenId) public virtual view returns (address) {
        address owner = tokenOwners[_tokenId];
        if (owner == address(0)) revert NullOwner();
        return owner;
    }

    function getApproved(uint _tokenId) public virtual view returns (address) {
        return tokenApprovals[_tokenId];
    }

    function isApprovedForAll(address _owner, address _spender) public virtual view returns (bool) {
        return operatorApprovals[_owner.normalize()][_spender.normalize()];
    }

    /*//////////////////////////////////////
                ERC-165 GETTERS
    //////////////////////////////////////*/

    function supportsInterface(bytes4 _interfaceId) public virtual view returns (bool) {
        return
            _interfaceId == 0x01ffc9a7 || // ERC165 Interface ID for ERC165
            _interfaceId == 0x80ac58cd || // ERC165 Interface ID for ERC721
            _interfaceId == 0x5b5e139f;   // ERC165 Interface ID for ERC721Metadata
    }

    /*//////////////////////////////////////
           MINT/BURN INTERNAL METHODS
    //////////////////////////////////////*/

    function _mint(address _to, uint _tokenId) internal virtual {
        // Attempt to normalize destination
        _to = _to.normalize();

        if (_to == address(0)) revert UnsafeReceiver();
        if (tokenOwners[_tokenId] != address(0)) revert Unauthorized();

        ownerBalances[_to]++;
        tokenOwners[_tokenId] = _to;

        emit Transfer(address(0), _to, _tokenId);
    }

    function _burn(uint _tokenId) internal virtual {
        address owner = ownerOf(_tokenId);

        ownerBalances[owner]--;
        delete tokenOwners[_tokenId];
        delete tokenApprovals[_tokenId];

        emit Transfer(owner, address(0), _tokenId);
    }

    function _safeMint(address _to, uint _tokenId) internal virtual {
        _mint(_to, _tokenId);

        // Check receiver. No normalization is needed:
        // - msg.sender is already normalized by default
        // - _to is getting called, which behaves identically for ID / Eth addresses
        // - address(0) doesn't need normalization
        _checkSafeReceiver(_to, msg.sender, address(0), _tokenId, "");
    }

    function _safeMint(address _to, uint _tokenId, bytes memory _data) internal virtual {
        _mint(_to, _tokenId);

        // Check receiver. No normalization is needed:
        // - msg.sender is already normalized by default
        // - _to is getting called, which behaves identically for ID / Eth addresses
        // - address(0) doesn't need normalization
        _checkSafeReceiver(_to, msg.sender, address(0), _tokenId, _data);
    }

    /**
     * @notice This method does NOT normalize inputs. Ensure addresses are
     * normalized before calling this method.
     */
    function _checkSafeReceiver(address _to, address _operator, address _from, uint _tokenId, bytes memory _data) internal {
        // Native actors (like the miner) will have a codesize of 1
        // However, they'd still need to return the magic value for
        // this to succeed.
        if (
            _to.code.length != 0 &&
                IERC721TokenReceiver(_to).onERC721Received(_operator, _from, _tokenId, _data) !=
                    IERC721TokenReceiver.onERC721Received.selector
        ) revert UnsafeReceiver();
    }
}
