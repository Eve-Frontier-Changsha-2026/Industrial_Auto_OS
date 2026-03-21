import { describe, it, expect, beforeEach } from "vitest";
import { SingleKeypairProvider } from "../../src/signer/single.js";

// SUI keystore: JSON array of base64 strings
// first byte = scheme flag (0x00 = Ed25519), then 32-byte secret key
const MOCK_KEYSTORE = JSON.stringify([
  "ANgGe3kmT3tFCr6lRzIYuEHXGHsJJF7nvPqXkxW/yfJx",
]);

describe("SingleKeypairProvider", () => {
  let provider: SingleKeypairProvider;

  beforeEach(() => {
    provider = SingleKeypairProvider.fromKeystoreContent(MOCK_KEYSTORE);
  });

  it("returns a keypair from getSigner", async () => {
    const kp = await provider.getSigner();
    expect(kp).toBeDefined();
    expect(kp.getPublicKey()).toBeDefined();
  });

  it("returns consistent address", async () => {
    const kp1 = await provider.getSigner();
    const kp2 = await provider.getSigner({ ruleHandler: "test" });
    expect(kp1.getPublicKey().toSuiAddress()).toBe(
      kp2.getPublicKey().toSuiAddress(),
    );
  });

  it("listSigners returns one entry", async () => {
    const signers = await provider.listSigners();
    expect(signers).toHaveLength(1);
    expect(signers[0].label).toBe("default");
    expect(signers[0].address).toMatch(/^0x/);
  });
});
