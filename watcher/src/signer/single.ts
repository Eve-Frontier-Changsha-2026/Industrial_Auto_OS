import { readFileSync } from "node:fs";
import { Ed25519Keypair } from "@mysten/sui/keypairs/ed25519";
import { decodeSuiPrivateKey } from "@mysten/sui/cryptography";
import type { Keypair } from "@mysten/sui/cryptography";
import type { SignerProvider, SignerContext, SignerInfo } from "./interface.js";

export class SingleKeypairProvider implements SignerProvider {
  private keypair: Ed25519Keypair;

  private constructor(keypair: Ed25519Keypair) {
    this.keypair = keypair;
  }

  static fromKeystoreFile(path: string): SingleKeypairProvider {
    const content = readFileSync(path, "utf-8");
    return SingleKeypairProvider.fromKeystoreContent(content);
  }

  static fromKeystoreContent(content: string): SingleKeypairProvider {
    const keys: string[] = JSON.parse(content);
    if (keys.length === 0) throw new Error("Keystore is empty");

    // SUI keystore format: base64(scheme_flag + secret_key_bytes)
    try {
      const { schema, secretKey } = decodeSuiPrivateKey(keys[0]);
      if (schema === "ED25519") {
        return new SingleKeypairProvider(
          Ed25519Keypair.fromSecretKey(secretKey),
        );
      }
    } catch {
      // Fallback: raw decode for older keystore format
    }

    const raw = Buffer.from(keys[0], "base64");
    const scheme = raw[0]; // 0x00 = Ed25519
    if (scheme !== 0x00)
      throw new Error(`Unsupported key scheme: ${scheme}`);
    return new SingleKeypairProvider(
      Ed25519Keypair.fromSecretKey(raw.subarray(1)),
    );
  }

  async getSigner(_context?: SignerContext): Promise<Keypair> {
    return this.keypair;
  }

  async listSigners(): Promise<SignerInfo[]> {
    return [
      {
        address: this.keypair.getPublicKey().toSuiAddress(),
        label: "default",
      },
    ];
  }
}
