// E2E claim helper for Foundry FFI tests.
// Usage: tsx e2e-claim-helper.ts <proofIndex>
// Outputs ABI-encoded (proof, publicInputs, stealthAddress, ephemeralPubKey, viewTag)

import { Barretenberg, UltraHonkBackend } from "@aztec/bb.js";
import { Noir } from "@noir-lang/noir_js";
import { ethers } from "ethers";
import { readFileSync } from "fs";
import { generateRandomStealthMetaAddress, buildUriMetaAddressFromPrivkeys } from "./generate-meta-address.js";
import { parseMetaAddress, generateStealthParameters } from "./generate-stealth-address.js";

function hexToBuffer(hex: string): Uint8Array {
  return Uint8Array.from(Buffer.from(hex.replace("0x", "").padStart(64, "0"), "hex"));
}

function bufferToHex(buf: Uint8Array): string {
  return "0x" + Buffer.from(buf).toString("hex");
}

async function main() {
  const [, , proofIndexArg] = process.argv;
  if (proofIndexArg === undefined) {
    console.error("Usage: tsx e2e-claim-helper.ts <proofIndex>");
    process.exit(1);
  }

  const proofIndex = Number(proofIndexArg);
  if (Number.isNaN(proofIndex) || proofIndex < 0) {
    console.error("proofIndex must be a non-negative integer");
    process.exit(1);
  }

  // 1. Generate stealth meta-address
  const meta = generateRandomStealthMetaAddress();
  const uri = buildUriMetaAddressFromPrivkeys(meta.spendPriv, meta.viewPriv);
  console.error("Meta-address generated:", uri.uri.slice(0, 30) + "...");

  // 2. Derive stealth address
  const { spendingPublicKeyHex, viewingPublicKeyHex } = parseMetaAddress(uri.uri);
  const stealth = generateStealthParameters(spendingPublicKeyHex, viewingPublicKeyHex);
  console.error("Stealth address:", stealth.stealthAddress);

  // 3. Generate ZK proof
  const circuit = JSON.parse(
    readFileSync(new URL("../../circuits/target/init.json", import.meta.url), "utf-8"),
  );

  const treeData = JSON.parse(
    readFileSync(new URL("./tree-data.json", import.meta.url), "utf-8"),
  );
  const root: string = treeData.root;
  const entry = treeData.proofs[proofIndex];
  if (!entry) {
    console.error(`No proof entry at index ${proofIndex}`);
    process.exit(1);
  }

  const bb = await Barretenberg.new();

  const { hash: nullifierHashBuf } = await bb.poseidon2Hash({
    inputs: [hexToBuffer(entry.nullifier_secret)],
  });
  const nullifierHash = bufferToHex(nullifierHashBuf);

  const recipientField =
    "0x" + BigInt(stealth.stealthAddress).toString(16).padStart(64, "0");

  const input = {
    root,
    nullifier_hash: nullifierHash,
    amount: entry.amount,
    recipient: recipientField,
    nullifier_secret: entry.nullifier_secret,
    eligible_address:
      "0x" + BigInt(entry.eligible_address).toString(16).padStart(64, "0"),
    merkle_proof: entry.merkle_proof.map((e: string) => e.toString()),
    is_even: entry.is_even,
  };

  console.error("Generating proof for index", proofIndex, "→", stealth.stealthAddress);

  // Suppress bb.js stdout to keep FFI output clean
  const origWrite = process.stdout.write.bind(process.stdout);
  process.stdout.write = (() => true) as any;

  const backend = new UltraHonkBackend(circuit.bytecode, bb);
  const noir = new Noir(circuit);
  const { witness } = await noir.execute(input);

  const { proof, publicInputs } = await backend.generateProof(witness, {
    verifierTarget: "evm",
  });

  process.stdout.write = origWrite;

  console.error(`Proof: ${proof.length} bytes, ${publicInputs.length} public inputs`);

  // 4. ABI-encode for Foundry FFI
  const publicInputsBytes32 = publicInputs.map(
    (v: string) => "0x" + BigInt(v).toString(16).padStart(64, "0"),
  );

  const encoded = ethers.AbiCoder.defaultAbiCoder().encode(
    ["bytes", "bytes32[]", "address", "bytes", "bytes1"],
    [
      proof,
      publicInputsBytes32,
      stealth.stealthAddress,
      stealth.ephemeralPublicKey,
      stealth.viewTag,
    ],
  );

  process.stdout.write(encoded);

  if (typeof backend.destroy === "function") await backend.destroy();
  if (typeof bb.destroy === "function") await bb.destroy();
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
