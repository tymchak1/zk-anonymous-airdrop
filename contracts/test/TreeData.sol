// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

library TreeData {
    Vm constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function loadRoot() internal view returns (bytes32) {
        string memory json = vm.readFile("js-scripts/tree-data.json");
        bytes memory raw = vm.parseJson(json, ".root");
        return abi.decode(raw, (bytes32));
    }

    function loadProof(uint256 idx)
        internal
        view
        returns (
            bytes32 nullifierHash,
            bytes32 nullifierSecret,
            address eligibleAddress,
            uint256 amount,
            bytes32 leaf,
            bytes32[20] memory merkleProof,
            bool[20] memory isEven
        )
    {
        string memory json = vm.readFile("js-scripts/tree-data.json");
        string memory base = string.concat(".proofs[", vm.toString(idx), "]");

        nullifierHash = abi.decode(vm.parseJson(json, string.concat(base, ".nullifier_hash")), (bytes32));
        nullifierSecret = abi.decode(vm.parseJson(json, string.concat(base, ".nullifier_secret")), (bytes32));
        eligibleAddress = abi.decode(vm.parseJson(json, string.concat(base, ".eligible_address")), (address));
        leaf = abi.decode(vm.parseJson(json, string.concat(base, ".leaf")), (bytes32));

        amount = vm.parseUint(abi.decode(vm.parseJson(json, string.concat(base, ".amount")), (string)));

        bytes32[] memory proofArr = abi.decode(vm.parseJson(json, string.concat(base, ".merkle_proof")), (bytes32[]));
        bool[] memory evenArr = abi.decode(vm.parseJson(json, string.concat(base, ".is_even")), (bool[]));

        for (uint256 i; i < 20; i++) {
            merkleProof[i] = proofArr[i];
            isEven[i] = evenArr[i];
        }
    }
}
