import { readFileSync, mkdirSync, writeFileSync } from "fs";
import { resolve, dirname } from "path";
import { fileURLToPath } from "url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const treeDataPath = resolve(__dirname, "tree-data.json");
const outputDir = resolve(__dirname, "../../claim-bundles");

interface Proof {
  index: number;
  nullifier_secret: string;
  eligible_address: string;
  amount: string;
  merkle_proof: string[];
  is_even: boolean[];
}

interface TreeData {
  root: string;
  proofs: Proof[];
}

const treeData: TreeData = JSON.parse(readFileSync(treeDataPath, "utf-8"));

mkdirSync(outputDir, { recursive: true });

let count = 0;
for (const proof of treeData.proofs) {
  const bundle = {
    index: proof.index,
    nullifier_secret: proof.nullifier_secret,
    amount: proof.amount,
    merkle_proof: proof.merkle_proof,
    is_even: proof.is_even,
  };

  const filePath = resolve(outputDir, `${proof.eligible_address}.json`);
  writeFileSync(filePath, JSON.stringify(bundle, null, 2) + "\n");
  count++;
}

console.log(`Exported ${count} claim bundles to claim-bundles/`);
