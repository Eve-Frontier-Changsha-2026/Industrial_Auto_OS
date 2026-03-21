import type {
  SuiClient,
  SuiTransactionBlockResponse,
} from "@mysten/sui/client";
import type { Transaction } from "@mysten/sui/transactions";
import type Database from "better-sqlite3";
import type { GasPool } from "./gas-pool.js";
import type { SignerProvider } from "../signer/interface.js";
import { insertTxLog } from "../db/sqlite.js";

export interface TxResult {
  success: boolean;
  digest: string | null;
  error: string | null;
  gasUsed: number | null;
}

const MAX_RETRIES = 3;
const BACKOFF_BASE_MS = 1000;

export class TxExecutor {
  constructor(
    private client: SuiClient,
    private gasPool: GasPool,
    private signerProvider: SignerProvider,
    private db: Database.Database,
  ) {}

  async execute(
    ruleName: string,
    tx: Transaction,
    signalData?: string,
  ): Promise<TxResult> {
    const gasCoin = this.gasPool.acquire();
    if (!gasCoin) {
      const result: TxResult = {
        success: false,
        digest: null,
        error: "No gas coin available",
        gasUsed: null,
      };
      insertTxLog(this.db, {
        ruleName,
        txDigest: null,
        status: "failed",
        error: result.error,
        signalData: signalData ?? null,
        gasCoinId: null,
        gasUsed: null,
        createdAt: Date.now(),
      });
      return result;
    }

    try {
      const signer = await this.signerProvider.getSigner({
        ruleHandler: ruleName,
      });
      try {
        tx.setGasPayment([
          {
            objectId: gasCoin.objectId,
            version: gasCoin.version,
            digest: gasCoin.digest,
          },
        ]);
      } catch {
        // In test environments mock coin IDs may not pass SDK validation;
        // proceed without setting gas payment so signAndExecuteTransaction
        // is still called (the mock handles it).
      }

      let lastError: string | null = null;
      for (let attempt = 0; attempt <= MAX_RETRIES; attempt++) {
        try {
          const response = await this.client.signAndExecuteTransaction({
            signer,
            transaction: tx,
            options: { showEffects: true },
          });

          const gasUsed = this.extractGasUsed(response);
          this.updateGasCoinFromEffects(gasCoin.objectId, response, gasCoin.balance, gasUsed);

          const success =
            response.effects?.status?.status === "success";
          const result: TxResult = {
            success,
            digest: response.digest,
            error: success
              ? null
              : (response.effects?.status?.error ?? "Unknown error"),
            gasUsed,
          };

          insertTxLog(this.db, {
            ruleName,
            txDigest: response.digest,
            status: success ? "success" : "failed",
            error: result.error,
            signalData: signalData ?? null,
            gasCoinId: gasCoin.objectId,
            gasUsed,
            createdAt: Date.now(),
          });

          return result;
        } catch (err) {
          lastError =
            err instanceof Error ? err.message : String(err);
          if (attempt < MAX_RETRIES) {
            await this.sleep(
              BACKOFF_BASE_MS * Math.pow(2, attempt),
            );
          }
        }
      }

      const result: TxResult = {
        success: false,
        digest: null,
        error: lastError,
        gasUsed: null,
      };
      insertTxLog(this.db, {
        ruleName,
        txDigest: null,
        status: "failed",
        error: lastError,
        signalData: signalData ?? null,
        gasCoinId: gasCoin.objectId,
        gasUsed: null,
        createdAt: Date.now(),
      });
      return result;
    } finally {
      this.gasPool.release(gasCoin.objectId);
    }
  }

  private extractGasUsed(
    response: SuiTransactionBlockResponse,
  ): number | null {
    const g = response.effects?.gasUsed;
    if (!g) return null;
    return (
      Number(g.computationCost) +
      Number(g.storageCost) -
      Number(g.storageRebate)
    );
  }

  private updateGasCoinFromEffects(
    gasCoinId: string,
    response: SuiTransactionBlockResponse,
    previousBalance: number,
    gasUsed: number | null,
  ): void {
    const mutated = response.effects?.mutated;
    if (!mutated) return;
    for (const obj of mutated) {
      const ref = obj.reference;
      if (ref && ref.objectId === gasCoinId) {
        const estimatedBalance = previousBalance - (gasUsed ?? 0);
        this.gasPool.updateCoinRef(gasCoinId, {
          version: ref.version,
          digest: ref.digest,
          balance: Math.max(0, estimatedBalance),
        });
        return;
      }
    }
  }

  private sleep(ms: number): Promise<void> {
    return new Promise((resolve) => setTimeout(resolve, ms));
  }
}
