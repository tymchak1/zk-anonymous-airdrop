import * as secp from "@noble/secp256k1";
import { hexlify, getBytes } from "ethers";

function ensure0x(s: string): string {
    return s.startsWith("0x") ? s : `0x${s}`;
}

function strip0x(s: string): string {
    return s.startsWith("0x") ? s.slice(2) : s;
}

export type StealthKeypair = {
    spendPriv: string;
    viewPriv: string;
    spendPubCompressed: string;
    viewPubCompressed: string;
    stealthMetaAddressHex: string;
};

export function generateStealthMetaAddressFromPrivkeys(
    spendPrivHex: string,
    viewPrivHex: string
): StealthKeypair {
    const spendPriv = getBytes(ensure0x(spendPrivHex));
    const viewPriv = getBytes(ensure0x(viewPrivHex));

    if (spendPriv.length !== 32 || viewPriv.length !== 32) {
        throw new Error("spendPriv / viewPriv must be 32-byte scalars");
    }

    const spendPubCompressed = secp.getPublicKey(spendPriv, true);
    const viewPubCompressed = secp.getPublicKey(viewPriv, true);

    const metaBytes = new Uint8Array(66);
    metaBytes.set(spendPubCompressed, 0);
    metaBytes.set(viewPubCompressed, 33);

    return {
        spendPriv: hexlify(spendPriv),
        viewPriv: hexlify(viewPriv),
        spendPubCompressed: hexlify(spendPubCompressed),
        viewPubCompressed: hexlify(viewPubCompressed),
        stealthMetaAddressHex: hexlify(metaBytes),
    };
}

export function generateRandomStealthMetaAddress(): StealthKeypair {
    const spendPriv = secp.utils.randomSecretKey();
    const viewPriv = secp.utils.randomSecretKey();
    return generateStealthMetaAddressFromPrivkeys(
        hexlify(spendPriv),
        hexlify(viewPriv)
    );
}

export type UriMetaAddress = {
    uri: string;
    spendPubUncompressed: string;
    viewPubUncompressed: string;
};

export function buildUriMetaAddressFromPrivkeys(
    spendPrivHex: string,
    viewPrivHex: string
): UriMetaAddress {
    const spendPriv = getBytes(ensure0x(spendPrivHex));
    const viewPriv = getBytes(ensure0x(viewPrivHex));

    const spendUncompressed = secp.getPublicKey(spendPriv, false);
    const viewUncompressed = secp.getPublicKey(viewPriv, false);

    const spendHex = strip0x(hexlify(spendUncompressed));
    const viewHex = strip0x(hexlify(viewUncompressed));

    const uri = `st:eth:0x${spendHex}${viewHex}`;

    return {
        uri,
        spendPubUncompressed: `0x${spendHex}`,
        viewPubUncompressed: `0x${viewHex}`,
    };
}

function main() {
    const args = process.argv.slice(2);
    const mode = args[0];

    if (!mode || mode === "gen") {
        const meta = generateRandomStealthMetaAddress();
        const uri = buildUriMetaAddressFromPrivkeys(meta.spendPriv, meta.viewPriv);
        console.log(
            JSON.stringify(
                {
                    schemeId: 1,
                    stealthMetaAddressHex: meta.stealthMetaAddressHex,
                    spendPriv: meta.spendPriv,
                    viewPriv: meta.viewPriv,
                    spendPubCompressed: meta.spendPubCompressed,
                    viewPubCompressed: meta.viewPubCompressed,
                    uriMetaAddress: uri.uri,
                    spendPubUncompressed: uri.spendPubUncompressed,
                    viewPubUncompressed: uri.viewPubUncompressed,
                },
                null,
                2
            )
        );
        return;
    }

    if (mode === "from-priv") {
        if (args.length < 3) {
            console.error("Usage: node stealth-meta-address.js from-priv <spendPriv> <viewPriv>");
            process.exit(1);
        }
        const spendPriv = args[1];
        const viewPriv = args[2];
        const meta = generateStealthMetaAddressFromPrivkeys(spendPriv, viewPriv);
        const uri = buildUriMetaAddressFromPrivkeys(meta.spendPriv, meta.viewPriv);
        console.log(
            JSON.stringify(
                {
                    schemeId: 1,
                    stealthMetaAddressHex: meta.stealthMetaAddressHex,
                    spendPriv: meta.spendPriv,
                    viewPriv: meta.viewPriv,
                    spendPubCompressed: meta.spendPubCompressed,
                    viewPubCompressed: meta.viewPubCompressed,
                    uriMetaAddress: uri.uri,
                    spendPubUncompressed: uri.spendPubUncompressed,
                    viewPubUncompressed: uri.viewPubUncompressed,
                },
                null,
                2
            )
        );
        return;
    }

    console.error(`Unknown mode: ${mode}`);
    process.exit(1);
}

const isDirectRun = process.argv[1]?.includes("generate-meta-address");
if (isDirectRun) {
    main();
}
