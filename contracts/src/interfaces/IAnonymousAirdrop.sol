// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

interface IAnonymousAirdrop {
    // ---- ERRORS ---- //
    error AlreadyClaimed();
    error InputNotInField();
    error InvalidProof();
    error TransferFailed();
    error ZeroParameters();

    // ---- EVENTS ---- //
    event Initialized(address indexed token, uint256 totalSupply, bytes32 merkleRoot, address indexed verifier);

    event Claimed(bytes32 indexed nullifierHash, address indexed stealthAddress, uint256 amount);
}
