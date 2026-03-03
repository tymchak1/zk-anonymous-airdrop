// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {IAnonymousAirdrop} from "./interfaces/IAnonymousAirdrop.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {IERC5564Announcer} from "./interfaces/IERC5564Announcer.sol";
import {IVerifier} from "./Verifier.sol";

// invariants:
// only Merkle tree members can claim ()
// only once
// to stealth address

contract AnonymousAirdrop is IAnonymousAirdrop {
    /// @dev BN254 scalar field modulus — all public inputs must be < this value
    uint256 private constant BN254_MODULUS =
        21888242871839275222246405745257275088548364400416034343698204186575808495617;

    mapping(bytes32 => bool) private s_nullifierHashes; // nullifier used -> claimed

    IERC20 private immutable i_token;
    uint256 private immutable i_totalSupply;

    bytes32 private immutable i_merkleRoot;

    IVerifier private immutable i_verifier;
    IERC5564Announcer private immutable i_announcer;

    // ---- FUNCTIONS ---- //
    constructor(
        IERC20 token,
        uint256 totalSupply,
        bytes32 merkleRoot,
        IVerifier verifier,
        IERC5564Announcer announcer
    ) {
        if (
            address(token) == address(0) || totalSupply == 0 || merkleRoot == bytes32(0)
                || address(verifier) == address(0)
        ) {
            revert ZeroParameters();
        }
        if (uint256(merkleRoot) >= BN254_MODULUS) revert InputNotInField();

        i_token = token;
        i_totalSupply = totalSupply;
        i_merkleRoot = merkleRoot;
        i_verifier = IVerifier(verifier);
        i_announcer = IERC5564Announcer(announcer);

        token.mint(address(this), totalSupply);
    }

    function claim(
        bytes calldata proof,
        bytes32 nullifierHash,
        uint256 amount,
        address stealthAddress,
        bytes calldata ephemeralPubKey,
        bytes1 viewTag
    ) external {
        if (uint256(nullifierHash) >= BN254_MODULUS) revert InputNotInField();
        if (amount >= BN254_MODULUS) revert InputNotInField();
        if (s_nullifierHashes[nullifierHash]) revert AlreadyClaimed();

        bytes32[] memory publicInputs = new bytes32[](4);
        publicInputs[0] = i_merkleRoot;
        publicInputs[1] = nullifierHash;
        publicInputs[2] = bytes32(amount);
        publicInputs[3] = bytes32(uint256(uint160(stealthAddress)));

        s_nullifierHashes[nullifierHash] = true;
        (bool success) = i_verifier.verify(proof, publicInputs);
        if (!success) revert InvalidProof();
        // we assume, that token returns bool after transfering
        if (!i_token.transfer(stealthAddress, amount)) revert TransferFailed();

        // NOTE: ephemeralPubKey/viewTag are not proof-bound — a front-runner could swap them,
        // causing a spoofed announcement.
        // Funds are safe (stealthAddress is proof-bound, user holds the key), but an ERC-5564
        // scanner would see wrong ephemeral data and fail to derive the spending key.
        // Only affects discovery, not ownership. In production, bind them to the proof.
        bytes memory metadata = abi.encodePacked(
            viewTag, // bytes1 — view tag
            bytes4(0xa9059cbb), // transfer selector
            address(i_token),
            amount
        );
        i_announcer.announce(1, stealthAddress, ephemeralPubKey, metadata);

        emit Claimed(nullifierHash, stealthAddress, amount);
    }

    // ---- GETTERS ---- //
    function getTotalSupply() external view returns (uint256) {
        return i_totalSupply;
    }

    function getMerkleRoot() external view returns (bytes32) {
        return i_merkleRoot;
    }

    function getToken() external view returns (address) {
        return address(i_token);
    }

    function getVerifier() external view returns (address) {
        return address(i_verifier);
    }

    function getAnnouncer() external view returns (address) {
        return address(i_announcer);
    }

    function hasClaimed(bytes32 nullifierHash) external view returns (bool) {
        return s_nullifierHashes[nullifierHash];
    }
}
