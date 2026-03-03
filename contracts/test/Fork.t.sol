// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test, console, Vm} from "forge-std/Test.sol";
import {AnonymousAirdrop} from "../src/AnonymousAirdrop.sol";
import {ERC20Mock} from "./mock/ERC20Mock.sol";
import {HonkVerifier} from "../src/Verifier.sol";
import {TreeData} from "./TreeData.sol";

import {IAnonymousAirdrop} from "../src/interfaces/IAnonymousAirdrop.sol";
import {IERC5564Announcer} from "../src/interfaces/IERC5564Announcer.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";
import {IVerifier} from "../src/Verifier.sol";

contract ForkTest is Test {
    AnonymousAirdrop airdrop;
    IERC20 token;
    IVerifier verifier;

    /// @dev Real ERC-5564 Announcer on Sepolia
    address constant ANNOUNCER = 0x55649E01B5Df198D18D95b5cc5051630cfD45564;

    uint256 constant TOTAL_SUPPLY = 1000000 * 1e18;

    /// @dev First Anvil address — has a claim bundle
    address constant ELIGIBLE = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));

        token = IERC20(new ERC20Mock());
        verifier = IVerifier(new HonkVerifier());

        bytes32 merkleRoot = TreeData.loadRoot();

        airdrop = new AnonymousAirdrop(token, TOTAL_SUPPLY, merkleRoot, verifier, IERC5564Announcer(ANNOUNCER));
    }

    struct ClaimData {
        bytes proof;
        bytes32[] publicInputs;
        address stealthAddress;
        bytes ephemeralPubKey;
        bytes1 viewTag;
        bytes32 nullifierHash;
        uint256 amount;
    }

    function _loadClaimData() internal returns (ClaimData memory c) {
        string memory bundlePath = string.concat("js-scripts/claim-bundles/", vm.toString(ELIGIBLE), ".json");
        string memory merkleRoot = vm.toString(airdrop.getMerkleRoot());
        string memory eligibleAddr = vm.toString(ELIGIBLE);

        string[] memory inputs = new string[](6);
        inputs[0] = "npx";
        inputs[1] = "tsx";
        inputs[2] = "js-scripts/fork-claim-helper.ts";
        inputs[3] = bundlePath;
        inputs[4] = merkleRoot;
        inputs[5] = eligibleAddr;

        bytes memory result = vm.ffi(inputs);

        (c.proof, c.publicInputs, c.stealthAddress, c.ephemeralPubKey, c.viewTag) =
            abi.decode(result, (bytes, bytes32[], address, bytes, bytes1));

        c.nullifierHash = c.publicInputs[1];
        c.amount = uint256(c.publicInputs[2]);

        assertTrue(c.proof.length > 0, "proof should not be empty");
        assertTrue(c.stealthAddress != address(0), "stealth address should not be zero");
        assertEq(c.publicInputs[0], airdrop.getMerkleRoot(), "root must match contract");
    }

    function test_claimFromBundle_emitsClaimed() public {
        ClaimData memory c = _loadClaimData();
        uint256 contractBalBefore = token.balanceOf(address(airdrop));
        address relayer = makeAddr("relayer");

        vm.expectEmit(true, true, false, true);
        emit IAnonymousAirdrop.Claimed(c.nullifierHash, c.stealthAddress, c.amount);

        vm.prank(relayer);
        airdrop.claim(c.proof, c.nullifierHash, c.amount, c.stealthAddress, c.ephemeralPubKey, c.viewTag);

        assertEq(token.balanceOf(c.stealthAddress), c.amount, "stealth address should receive tokens");
        assertEq(token.balanceOf(relayer), 0, "relayer should receive nothing");
        assertEq(token.balanceOf(address(airdrop)), contractBalBefore - c.amount, "contract balance should decrease");
        assertTrue(airdrop.hasClaimed(c.nullifierHash), "nullifier should be marked claimed");
    }

    function test_claimFromBundle_emitsAnnouncement() public {
        ClaimData memory c = _loadClaimData();
        address relayer = makeAddr("relayer");

        vm.expectEmit(true, true, true, true, ANNOUNCER);
        bytes memory expectedMetadata = abi.encodePacked(c.viewTag, bytes4(0xa9059cbb), address(token), c.amount);
        emit IERC5564Announcer.Announcement(1, c.stealthAddress, address(airdrop), c.ephemeralPubKey, expectedMetadata);

        vm.prank(relayer);
        airdrop.claim(c.proof, c.nullifierHash, c.amount, c.stealthAddress, c.ephemeralPubKey, c.viewTag);
    }

    /// Simulates stealth address scanner: filter logs → parse viewTag → decode metadata
    function test_claimFromBundle_announcementIsIndexable() public {
        ClaimData memory c = _loadClaimData();
        address relayer = makeAddr("relayer");

        vm.recordLogs();

        vm.prank(relayer);
        airdrop.claim(c.proof, c.nullifierHash, c.amount, c.stealthAddress, c.ephemeralPubKey, c.viewTag);

        Vm.Log[] memory logs = vm.getRecordedLogs();

        // ── Find the Announcement log from the Announcer contract ──
        bytes32 announcementTopic = keccak256("Announcement(uint256,address,address,bytes,bytes)");
        Vm.Log memory ann;
        bool found;
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].emitter == ANNOUNCER && logs[i].topics[0] == announcementTopic) {
                ann = logs[i];
                found = true;
                break;
            }
        }
        assertTrue(found, "Announcement event not found from Announcer");

        // ── 1. Indexed topics — what a scanner filters on ──
        // topic[1] = schemeId (scanner picks scheme 1 for secp256k1)
        assertEq(uint256(ann.topics[1]), 1, "schemeId must be 1 (secp256k1)");

        // topic[2] = stealthAddress (scanner matches against derived addresses)
        address logStealthAddr = address(uint160(uint256(ann.topics[2])));
        assertEq(logStealthAddr, c.stealthAddress, "indexed stealthAddress must match");

        // topic[3] = caller (the contract that called announce())
        address logCaller = address(uint160(uint256(ann.topics[3])));
        assertEq(logCaller, address(airdrop), "indexed caller must be the airdrop contract");

        // ── 2. Decode non-indexed data (ephemeralPubKey, metadata) ──
        (bytes memory logEphemeralPubKey, bytes memory logMetadata) = abi.decode(ann.data, (bytes, bytes));

        // ── 3. ephemeralPubKey — scanner needs this for ECDH derivation ──
        assertEq(logEphemeralPubKey.length, 65, "ephemeralPubKey must be 65 bytes (0x04 || x || y)");
        assertEq(keccak256(logEphemeralPubKey), keccak256(c.ephemeralPubKey), "ephemeralPubKey must match FFI output");

        // ── 4. Metadata parsing — simulates scanner's decode logic ──
        // Layout: viewTag (1) | selector (4) | token address (20) | amount (32) = 57 bytes
        assertEq(logMetadata.length, 57, "metadata must be 57 bytes (1+4+20+32)");

        // viewTag — first byte, cheap pre-filter before expensive ECDH
        bytes1 logViewTag = logMetadata[0];
        assertEq(logViewTag, c.viewTag, "viewTag must match - scanner uses this to skip non-matching events");

        // transfer selector — bytes [1:5]
        bytes4 logSelector;
        assembly {
            logSelector := mload(add(logMetadata, 0x21))
        }
        assertEq(logSelector, bytes4(0xa9059cbb), "selector must be transfer(address,uint256)");

        // token address — bytes [5:25]
        address logToken;
        assembly {
            logToken := shr(96, mload(add(logMetadata, 0x25)))
        }
        assertEq(logToken, address(token), "token address must match");

        // amount — bytes [25:57]
        uint256 logAmount;
        assembly {
            logAmount := mload(add(logMetadata, 0x39))
        }
        assertEq(logAmount, c.amount, "amount must match claimed amount");
    }
}
