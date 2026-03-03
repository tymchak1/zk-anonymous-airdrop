// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Script} from "forge-std/Script.sol";
import {ERC20Mock} from "../test/mock/ERC20Mock.sol";

// UPDATE WITH VALID DATA

contract HelperConfig is Script {
    struct NetworkConfig {
        address token;
        uint256 totalSupply;
        bytes32 merkleRoot;
        address verifier;
        address announcer;
    }

    NetworkConfig public activeNetworkConfig;
    uint256 constant TOTAL_SUPPLY = 1000000 * 1e18;

    constructor() {
        if (block.chainid == 11155111) {
            activeNetworkConfig = getSepoliaEthConfig();
        } else if (block.chainid == 1) {
            activeNetworkConfig = getMainnetEthConfig();
        } else {
            activeNetworkConfig = getAnvilConfig();
        }
    }

    function getSepoliaEthConfig() public pure returns (NetworkConfig memory) {
        return NetworkConfig({
            token: 0x0000000000000000000000000000000000000001,
            totalSupply: TOTAL_SUPPLY,
            merkleRoot: bytes32("1"),
            verifier: 0x0000000000000000000000000000000000000001,
            announcer: 0x0000000000000000000000000000000000000001
        });
    }

    function getMainnetEthConfig() public pure returns (NetworkConfig memory) {
        return NetworkConfig({
            token: 0x0000000000000000000000000000000000000001,
            totalSupply: TOTAL_SUPPLY,
            merkleRoot: bytes32("1"),
            verifier: 0x0000000000000000000000000000000000000001,
            announcer: 0x0000000000000000000000000000000000000001
        });
    }

    function getAnvilConfig() public returns (NetworkConfig memory) {
        ERC20Mock token = new ERC20Mock();

        return NetworkConfig({
            token: address(token),
            totalSupply: TOTAL_SUPPLY,
            merkleRoot: bytes32("1"),
            verifier: 0x0000000000000000000000000000000000000001,
            announcer: 0x0000000000000000000000000000000000000001
        });
    }
}
