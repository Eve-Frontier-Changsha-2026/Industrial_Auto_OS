import type { SuiClient } from "@mysten/sui/client";
import type { GasCoinEntry } from "../types.js";

export interface GasPoolConfig {
  poolSize: number;
  minCoinBalance: number;
  minBalanceWarn: number;
}

export class GasPool {
  private coins: GasCoinEntry[] = [];
  private acquired = new Set<string>();
  private nextIndex = 0;

  constructor(
    private client: SuiClient,
    private ownerAddress: string,
    private config: GasPoolConfig,
  ) {}

  async initialize(): Promise<void> {
    const result = await this.client.getCoins({
      owner: this.ownerAddress,
      coinType: "0x2::sui::SUI",
    });

    this.coins = result.data.map((c) => ({
      objectId: c.coinObjectId,
      version: c.version,
      digest: c.digest,
      balance: Number(c.balance),
    }));
  }

  size(): number {
    return this.coins.length;
  }

  acquire(): GasCoinEntry | null {
    const available = this.coins.filter(
      (c) => !this.acquired.has(c.objectId),
    );
    if (available.length === 0) return null;
    const coin = available[this.nextIndex % available.length];
    this.nextIndex++;
    this.acquired.add(coin.objectId);
    return coin;
  }

  release(objectId: string): void {
    this.acquired.delete(objectId);
  }

  updateCoinRef(
    objectId: string,
    update: { version: string; digest: string; balance: number },
  ): void {
    const coin = this.coins.find((c) => c.objectId === objectId);
    if (coin) {
      coin.version = update.version;
      coin.digest = update.digest;
      coin.balance = update.balance;
    }
  }

  totalBalance(): number {
    return this.coins.reduce((sum, c) => sum + c.balance, 0);
  }

  isLowBalance(): boolean {
    return this.totalBalance() < this.config.minBalanceWarn;
  }

  isCriticalBalance(): boolean {
    return this.totalBalance() < this.config.minBalanceWarn / 2;
  }
}
