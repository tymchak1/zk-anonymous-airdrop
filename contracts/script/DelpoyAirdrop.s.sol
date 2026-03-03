// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Script, console2} from "forge-std/Script.sol";
import {AnonymousAirdrop} from "../src/AnonymousAirdrop.sol";
import {HonkVerifier} from "../src/Verifier.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

import {IERC5564Announcer} from "../src/interfaces/IERC5564Announcer.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";

contract DeployAirdrop is Script {
    AnonymousAirdrop airdrop;

    function run() public returns (AnonymousAirdrop, HelperConfig) {
        (AnonymousAirdrop airdropInstance, HelperConfig config) = deployAirdrop();
        return (airdropInstance, config);
    }

    function deployAirdrop() public returns (AnonymousAirdrop, HelperConfig) {
        HelperConfig config = new HelperConfig();
        (address token, uint256 totalSupply, bytes32 merkleRoot, address verifier, address announcer) =
            config.activeNetworkConfig();

        vm.startBroadcast();
        AnonymousAirdrop airdropInstance = new AnonymousAirdrop(
            IERC20(token), totalSupply, merkleRoot, HonkVerifier(address(verifier)), IERC5564Announcer(announcer)
        );
        vm.stopBroadcast();

        console2.log("AnonymousAirdrop deployed at:", address(airdropInstance));
        return (airdropInstance, config);
    }
}
