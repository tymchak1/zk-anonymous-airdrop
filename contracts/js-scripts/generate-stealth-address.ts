import * as secp from '@noble/secp256k1';
import { keccak256, getBytes, hexlify, computeAddress } from 'ethers';

export function parseMetaAddress(metaAddress: string) {
    const parts = metaAddress.split(':');
    if (parts.length < 3) throw new Error("Invalid meta-address format");

    const keysPart = parts[2].replace('0x', '');

    if (keysPart.length !== 260) {
        throw new Error("Expected 130-byte uncompressed keys concatenated");
    }

    const spendingPublicKeyHex = "0x" + keysPart.slice(0, 130);
    const viewingPublicKeyHex = "0x" + keysPart.slice(130, 260);

    return { spendingPublicKeyHex, viewingPublicKeyHex };
}

export function generateStealthParameters(
    spendingPublicKeyHex: string,
    viewingPublicKeyHex: string
) {
    const spendPub = spendingPublicKeyHex.replace('0x', '');
    const viewPub = viewingPublicKeyHex.replace('0x', '');

    const ephemeralPrivateKey = secp.utils.randomSecretKey();

    const ephemeralPublicKey = secp.getPublicKey(ephemeralPrivateKey, false);
    const ephemeralPublicKeyHex = hexlify(ephemeralPublicKey);

    const viewPubBytes = Uint8Array.from(Buffer.from(viewPub, 'hex'));
    const sharedSecret = secp.getSharedSecret(ephemeralPrivateKey, viewPubBytes, false);

    const sharedSecretHash = keccak256(sharedSecret);
    const hashedSecretBytes = getBytes(sharedSecretHash);

    const viewTag = hexlify(hashedSecretBytes.slice(0, 1));

    const scalar = BigInt(sharedSecretHash);
    const hG = secp.Point.BASE.multiply(scalar);
    const P_spend = secp.Point.fromHex(spendPub);
    const P_stealth = P_spend.add(hG);

    const stealthPublicKeyHex = "0x" + P_stealth.toHex(false);
    const stealthAddress = computeAddress(stealthPublicKeyHex);

    return {
        stealthAddress,
        ephemeralPublicKey: ephemeralPublicKeyHex,
        viewTag,
    };
}

function main() {
    const args = process.argv.slice(2);

    if (args.length < 1) {
        console.error("Usage: ts-node 2-generate-stealth.ts <metaAddress>");
        process.exit(1);
    }

    const metaAddress = args[0];

    try {
        const { spendingPublicKeyHex, viewingPublicKeyHex } = parseMetaAddress(metaAddress);
        const result = generateStealthParameters(spendingPublicKeyHex, viewingPublicKeyHex);
        console.log(JSON.stringify(result, null, 2));
    } catch (error: any) {
        console.error("Error:", error.message);
        process.exit(1);
    }
}

const isDirectRun = process.argv[1]?.includes("generate-stealth-address");
if (isDirectRun) {
    main();
}