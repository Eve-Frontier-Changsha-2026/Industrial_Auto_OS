import type { MockDamageReport } from "../types.js";

export interface FleetListenerConfig {
  mock: boolean;
  intervalMs: number;
  recipeIds: string[];
  onReport: (report: MockDamageReport) => void;
}

export class FleetListener {
  private timer: ReturnType<typeof setInterval> | null = null;

  constructor(private config: FleetListenerConfig) {}

  start(): void {
    if (!this.config.mock) return;
    if (this.config.recipeIds.length === 0) return;

    this.timer = setInterval(() => {
      const report = this.generateReport();
      this.config.onReport(report);
    }, this.config.intervalMs);
  }

  stop(): void {
    if (this.timer) {
      clearInterval(this.timer);
      this.timer = null;
    }
  }

  private generateReport(): MockDamageReport {
    const recipeId =
      this.config.recipeIds[
        Math.floor(Math.random() * this.config.recipeIds.length)
      ];
    return {
      recipeId,
      quantity: Math.floor(Math.random() * 10) + 1,
      priority: 3,
      description: `Fleet damage report: ${recipeId} — automated mock`,
    };
  }
}
