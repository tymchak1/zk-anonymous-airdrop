import { Barretenberg, UltraHonkBackend } from "@aztec/bb.js";
import { Noir } from "@noir-lang/noir_js";
import { ethers } from "ethers";
import { readFileSync } from "fs";

// ── Usage ────────────────────────────────────────────────────────────
// tsx generate-proof.ts <proofIndex> <recipientAddress>
// Outputs ABI-encoded (bytes proof, bytes32[] publicInputs) to stdout

function hexToBuffer(hex: string): Uint8Array {
  return Uint8Array.from(Buffer.from(hex.replace("0x", "").padStart(64, "0"), "hex"));
}

function bufferToHex(buf: Uint8Array): string {
  return "0x" + Buffer.from(buf).toString("hex");
}

async function main() {
  const [, , proofIndexArg, recipientArg] = process.argv;
  if (proofIndexArg === undefined || recipientArg === undefined) {
    console.error("Usage: tsx generate-proof.ts <proofIndex> <recipientAddress>");
    process.exit(1);
  }

  const proofIndex = Number(proofIndexArg);
  if (Number.isNaN(proofIndex) || proofIndex < 0) {
    console.error("proofIndex must be a non-negative integer");
    process.exit(1);
  }

  // ── Load circuit artifact ────────────────────────────────────────
  const circuit = JSON.parse(
    readFileSync(new URL("../../circuits/target/init.json", import.meta.url), "utf-8"),
  );

  // ── Load tree data ───────────────────────────────────────────────
  const treeData = JSON.parse(readFileSync(new URL("./tree-data.json", import.meta.url), "utf-8"));
  const root: string = treeData.root;
  const entry = treeData.proofs[proofIndex];
  if (!entry) {
    console.error(`No proof entry at index ${proofIndex}`);
    process.exit(1);
  }

  // ── Initialize Barretenberg ────────────────────────────────────────
  const bb = await Barretenberg.new();

  // ── Compute nullifier_hash from nullifier_secret ───────────────────
  // nullifier_hash = Poseidon2(nullifier_secret) — matches circuit logic
  const { hash: nullifierHashBuf } = await bb.poseidon2Hash({
    inputs: [hexToBuffer(entry.nullifier_secret)],
  });
  const nullifierHash = bufferToHex(nullifierHashBuf);

  // ── Build circuit inputs ─────────────────────────────────────────
  const recipientField = "0x" + BigInt(recipientArg).toString(16).padStart(64, "0");

  const input = {
    // Public
    root,
    nullifier_hash: nullifierHash,
    amount: entry.amount,
    recipient: recipientField,
    // Private
    nullifier_secret: entry.nullifier_secret,
    eligible_address:
      "0x" + BigInt(entry.eligible_address).toString(16).padStart(64, "0"),
    merkle_proof: entry.merkle_proof.map((e: string) => e.toString()),
    is_even: entry.is_even,
  };

  console.error("Generating proof for index", proofIndex, "→", recipientArg);

  // ── Execute circuit (witness gen) ────────────────────────────────
  const backend = new UltraHonkBackend(circuit.bytecode, bb);
  const noir = new Noir(circuit);
  const { witness } = await noir.execute(input);

  // ── Generate proof (EVM-compatible) ──────────────────────────────
  const { proof, publicInputs } = await backend.generateProof(witness, {
    verifierTarget: "evm",
  });

  console.error(`Proof generated: ${proof.length} bytes, ${publicInputs.length} public inputs`);

  // ── ABI-encode for contract consumption ──────────────────────────
  // publicInputs from noir_js are hex strings — pad to bytes32
  const publicInputsBytes32 = publicInputs.map(
    (v: string) => "0x" + BigInt(v).toString(16).padStart(64, "0"),
  );

  const encoded = ethers.AbiCoder.defaultAbiCoder().encode(
    ["bytes", "bytes32[]"],
    [proof, publicInputsBytes32],
  );

  // Write raw bytes to stdout (consumed by Foundry FFI)
  process.stdout.write(encoded);
  console.error("ABI-encoded output written to stdout");

  await backend.destroy();
  await bb.destroy();
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
