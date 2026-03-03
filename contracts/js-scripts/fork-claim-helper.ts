// Fork-test claim helper — reads a claim bundle JSON instead of tree-data.json.
// Usage: tsx fork-claim-helper.ts <bundlePath> <merkleRoot> <eligibleAddress>
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
  const [, , bundlePath, merkleRoot, eligibleAddress] = process.argv;
  if (!bundlePath || !merkleRoot || !eligibleAddress) {
    console.error("Usage: tsx fork-claim-helper.ts <bundlePath> <merkleRoot> <eligibleAddress>");
    process.exit(1);
  }

  // 1. Read claim bundle
  const bundle = JSON.parse(readFileSync(bundlePath, "utf-8"));
  console.error("Bundle loaded for index", bundle.index);

  // 2. Generate stealth meta-address
  const meta = generateRandomStealthMetaAddress();
  const uri = buildUriMetaAddressFromPrivkeys(meta.spendPriv, meta.viewPriv);
  console.error("Meta-address generated:", uri.uri.slice(0, 30) + "...");

  // 3. Derive stealth address
  const { spendingPublicKeyHex, viewingPublicKeyHex } = parseMetaAddress(uri.uri);
  const stealth = generateStealthParameters(spendingPublicKeyHex, viewingPublicKeyHex);
  console.error("Stealth address:", stealth.stealthAddress);

  // 4. Compute nullifier hash
  const bb = await Barretenberg.new();

  const { hash: nullifierHashBuf } = await bb.poseidon2Hash({
    inputs: [hexToBuffer(bundle.nullifier_secret)],
  });
  const nullifierHash = bufferToHex(nullifierHashBuf);

  // 5. Build circuit input
  const recipientField =
    "0x" + BigInt(stealth.stealthAddress).toString(16).padStart(64, "0");
  const eligibleField =
    "0x" + BigInt(eligibleAddress).toString(16).padStart(64, "0");

  const input = {
    root: merkleRoot,
    nullifier_hash: nullifierHash,
    amount: bundle.amount,
    recipient: recipientField,
    nullifier_secret: bundle.nullifier_secret,
    eligible_address: eligibleField,
    merkle_proof: bundle.merkle_proof.map((e: string) => e.toString()),
    is_even: bundle.is_even,
  };

  console.error("Generating proof for", eligibleAddress, "→", stealth.stealthAddress);

  // 6. Generate UltraHonk proof
  const circuit = JSON.parse(
    readFileSync(new URL("../../circuits/target/init.json", import.meta.url), "utf-8"),
  );

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

  // 7. ABI-encode for Foundry FFI
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
