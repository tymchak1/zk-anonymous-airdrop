// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

interface IERC5564Announcer {
    function announce(uint256 schemeId, address stealthAddress, bytes memory ephemeralPubKey, bytes memory metadata)
        external;

    event Announcement(
        uint256 indexed schemeId,
        address indexed stealthAddress,
        address indexed caller,
        bytes ephemeralPubKey,
        bytes metadata
    );
}
