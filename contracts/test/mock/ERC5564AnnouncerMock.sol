// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;
import {IERC5564Announcer} from "../../src/interfaces/IERC5564Announcer.sol";

contract ERC5564AnnouncerMock is IERC5564Announcer {
    function announce(uint256 schemeId, address stealthAddress, bytes memory ephemeralPubKey, bytes memory metadata)
        external
        override
    {
        emit Announcement(schemeId, stealthAddress, msg.sender, ephemeralPubKey, metadata);
    }
}
