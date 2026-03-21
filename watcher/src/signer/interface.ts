import type { Keypair } from "@mysten/sui/cryptography";

export interface SignerContext {
  ruleHandler: string;
  productionLineId?: string;
}

export interface SignerInfo {
  address: string;
  label: string;
}

export interface SignerProvider {
  getSigner(context?: SignerContext): Promise<Keypair>;
  listSigners(): Promise<SignerInfo[]>;
}
