// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IERC721TokenReceiver {
    function onERC721Received(
        address,
        address,
        uint,
        bytes calldata
    ) external returns (bytes4);
}