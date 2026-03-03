// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {AnonymousAirdrop} from "../src/AnonymousAirdrop.sol";
import {ERC5564AnnouncerMock, IERC5564Announcer} from "./mock/ERC5564AnnouncerMock.sol";
import {ERC20Mock} from "./mock/ERC20Mock.sol";
import {HonkVerifier} from "../src/Verifier.sol";
import {TreeData} from "./TreeData.sol";

import {DeployAirdrop} from "../script/DelpoyAirdrop.s.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";

import {IAnonymousAirdrop} from "../src/interfaces/IAnonymousAirdrop.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";
import {IVerifier} from "../src/Verifier.sol";

contract IntegrationTests is Test {
    AnonymousAirdrop airdrop;
    IERC20 token;
    IVerifier verifier;
    IERC5564Announcer announcer;

    uint256 constant TOTAL_SUPPLY = 1000000 * 1e18;

    function setUp() public {
        bytes32 merkleRoot = TreeData.loadRoot();

        token = IERC20(new ERC20Mock());
        verifier = IVerifier(new HonkVerifier());
        announcer = IERC5564Announcer(new ERC5564AnnouncerMock());
        airdrop = new AnonymousAirdrop(token, TOTAL_SUPPLY, merkleRoot, verifier, announcer);
    }

    function test_initial() public view {
        assertEq(token.totalSupply(), TOTAL_SUPPLY);
        assertEq(token.balanceOf(address(airdrop)), TOTAL_SUPPLY);
    }

    function test_claim_viaRelayer() public {
        // user generates proof + stealth address off-chain
        string[] memory inputs = new string[](3);
        inputs[0] = "npx";
        inputs[1] = "tsx";
        inputs[2] = "js-scripts/e2e-claim-helper.ts";
        inputs = _appendArg(inputs, "0");

        bytes memory result = vm.ffi(inputs);

        (
            bytes memory proof,
            bytes32[] memory publicInputs,
            address stealthAddress,
            bytes memory ephemeralPubKey,
            bytes1 viewTag
        ) = abi.decode(result, (bytes, bytes32[], address, bytes, bytes1));

        bytes32 nullifierHash = publicInputs[1];
        uint256 amount = uint256(publicInputs[2]);

        console.log("--- User sends to relayer (off-chain) ---");
        console.log("Proof size:", proof.length);
        console.log("Stealth address:", stealthAddress);
        console.log("Nullifier hash:", uint256(nullifierHash));
        console.log("Amount:", amount);
        console.log("Merkle root:", uint256(publicInputs[0]));

        assertTrue(proof.length > 0, "proof should not be empty");
        assertTrue(stealthAddress != address(0), "stealth address should not be zero");
        assertEq(publicInputs[0], airdrop.getMerkleRoot(), "root must match contract");

        uint256 contractBalBefore = token.balanceOf(address(airdrop));

        // relayer submits on-chain — msg.sender is relayer, not the eligible user
        address relayer = makeAddr("relayer");
        console.log("--- Relayer submits on-chain ---");
        console.log("Relayer:", relayer);

        // Expect Claimed event from the airdrop
        vm.expectEmit(true, true, false, true);
        emit IAnonymousAirdrop.Claimed(nullifierHash, stealthAddress, amount);

        vm.prank(relayer);
        airdrop.claim(proof, nullifierHash, amount, stealthAddress, ephemeralPubKey, viewTag);

        console.log("--- Result ---");
        console.log("Stealth balance:", token.balanceOf(stealthAddress));
        console.log("Relayer balance:", token.balanceOf(relayer));
        console.log("Contract balance:", token.balanceOf(address(airdrop)));
        console.log("Nullifier claimed:", airdrop.hasClaimed(nullifierHash));

        // tokens go to stealth address, not the relayer
        assertEq(token.balanceOf(stealthAddress), amount, "stealth address should receive tokens");
        assertEq(token.balanceOf(relayer), 0, "relayer should receive nothing");
        assertEq(token.balanceOf(address(airdrop)), contractBalBefore - amount, "contract balance should decrease");
        assertTrue(airdrop.hasClaimed(nullifierHash), "nullifier should be marked claimed");
    }

    function test_revert_AlreadyClaimed() public {
        string[] memory inputs = new string[](3);
        inputs[0] = "npx";
        inputs[1] = "tsx";
        inputs[2] = "js-scripts/e2e-claim-helper.ts";
        inputs = _appendArg(inputs, "0");

        bytes memory result = vm.ffi(inputs);

        (
            bytes memory proof,
            bytes32[] memory publicInputs,
            address stealthAddress,
            bytes memory ephemeralPubKey,
            bytes1 viewTag
        ) = abi.decode(result, (bytes, bytes32[], address, bytes, bytes1));

        bytes32 nullifierHash = publicInputs[1];
        uint256 amount = uint256(publicInputs[2]);

        airdrop.claim(proof, nullifierHash, amount, stealthAddress, ephemeralPubKey, viewTag);

        vm.expectRevert(IAnonymousAirdrop.AlreadyClaimed.selector);
        airdrop.claim(proof, nullifierHash, amount, stealthAddress, ephemeralPubKey, viewTag);
    }

    function test_revert_InvalidProof_modifiedAmount() public {
        string[] memory inputs = new string[](3);
        inputs[0] = "npx";
        inputs[1] = "tsx";
        inputs[2] = "js-scripts/e2e-claim-helper.ts";
        inputs = _appendArg(inputs, "0");

        bytes memory result = vm.ffi(inputs);

        (
            bytes memory proof,
            bytes32[] memory publicInputs,
            address stealthAddress,
            bytes memory ephemeralPubKey,
            bytes1 viewTag
        ) = abi.decode(result, (bytes, bytes32[], address, bytes, bytes1));

        bytes32 nullifierHash = publicInputs[1];
        uint256 tamperedAmount = uint256(publicInputs[2]) + 1 ether;

        vm.expectRevert();
        airdrop.claim(proof, nullifierHash, tamperedAmount, stealthAddress, ephemeralPubKey, viewTag);
    }

    function test_revert_InvalidProof_modifiedStealthAddress() public {
        string[] memory inputs = new string[](3);
        inputs[0] = "npx";
        inputs[1] = "tsx";
        inputs[2] = "js-scripts/e2e-claim-helper.ts";
        inputs = _appendArg(inputs, "0");

        bytes memory result = vm.ffi(inputs);

        (bytes memory proof, bytes32[] memory publicInputs,, bytes memory ephemeralPubKey, bytes1 viewTag) =
            abi.decode(result, (bytes, bytes32[], address, bytes, bytes1));

        bytes32 nullifierHash = publicInputs[1];
        uint256 amount = uint256(publicInputs[2]);
        address tamperedStealth = makeAddr("attacker");

        vm.expectRevert();
        airdrop.claim(proof, nullifierHash, amount, tamperedStealth, ephemeralPubKey, viewTag);
    }

    function test_revert_InvalidProof_tamperedProofBytes() public {
        string[] memory inputs = new string[](3);
        inputs[0] = "npx";
        inputs[1] = "tsx";
        inputs[2] = "js-scripts/e2e-claim-helper.ts";
        inputs = _appendArg(inputs, "0");

        bytes memory result = vm.ffi(inputs);

        (
            bytes memory proof,
            bytes32[] memory publicInputs,
            address stealthAddress,
            bytes memory ephemeralPubKey,
            bytes1 viewTag
        ) = abi.decode(result, (bytes, bytes32[], address, bytes, bytes1));

        proof[proof.length - 1] = proof[proof.length - 1] ^ 0xff;

        vm.expectRevert();
        airdrop.claim(proof, publicInputs[1], uint256(publicInputs[2]), stealthAddress, ephemeralPubKey, viewTag);
    }

    function _appendArg(string[] memory arr, string memory arg) internal pure returns (string[] memory) {
        string[] memory newArr = new string[](arr.length + 1);
        for (uint256 i; i < arr.length; i++) {
            newArr[i] = arr[i];
        }
        newArr[arr.length] = arg;
        return newArr;
    }

    function test_deployScript() public {
        DeployAirdrop deployer = new DeployAirdrop();
        (AnonymousAirdrop airdropInstance, HelperConfig config) = deployer.deployAirdrop();

        (address tokenAddr, uint256 totalSupply, bytes32 merkleRoot, address verifierAddr, address announcerAddr) =
            config.activeNetworkConfig();

        assertEq(address(airdropInstance) != address(0), true, "Airdrop contract should be deployed");
        assertEq(address(airdropInstance.getToken()), tokenAddr, "Token address should match config");
        assertEq(
            IERC20(tokenAddr).balanceOf(address(airdropInstance)),
            totalSupply,
            "Airdrop contract should hold total supply"
        );
        assertEq(address(airdropInstance.getVerifier()), verifierAddr, "Verifier address should match config");
        assertEq(airdropInstance.getAnnouncer(), announcerAddr, "Announcer address should match config");
        assertEq(airdropInstance.getMerkleRoot(), merkleRoot, "Merkle root should match config");
    }
}
