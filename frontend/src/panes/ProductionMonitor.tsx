import { useState } from "react";
import {
  useCurrentAccount,
  useSignAndExecuteTransaction,
} from "@mysten/dapp-kit";
import { useQueryClient } from "@tanstack/react-query";
import { useProductionLines } from "../hooks/useProductionLines";
import { useRecipes } from "../hooks/useRecipes";
import { useBlueprints } from "../hooks/useBlueprints";
import { StatusBadge } from "../components/StatusBadge";
import { useToast } from "../hooks/useToast";
import { humanError } from "../lib/errors";
import { PRODUCTION_STATUS } from "../lib/types";
import { PACKAGE_IDS } from "../lib/constants";
import { truncateAddress, formatDuration } from "../lib/format";
import {
  buildStartProduction,
  buildCompleteProduction,
  buildDepositFuel,
} from "../lib/ptb/production";
import styles from "./ProductionMonitor.module.css";

const LINE_IDS = (import.meta.env.VITE_PRODUCTION_LINE_IDS ?? "")
  .split(",")
  .filter(Boolean);

export function ProductionMonitor() {
  const account = useCurrentAccount();
  const { mutate: signAndExecute } = useSignAndExecuteTransaction();
  const queryClient = useQueryClient();
  const { addToast } = useToast();

  const { data: lines = [] } = useProductionLines(LINE_IDS);
  const { data: recipes = [] } = useRecipes();
  const { bpos } = useBlueprints();

  const [selectedRecipe, setSelectedRecipe] = useState<Record<string, string>>({});
  const [selectedBpo, setSelectedBpo] = useState<Record<string, string>>({});
  const [fuelAmount, setFuelAmount] = useState<Record<string, string>>({});

  const invalidate = () =>
    queryClient.invalidateQueries({ queryKey: ["production-lines"] });

  const handleStart = (lineId: string) => {
    const recipeId = selectedRecipe[lineId];
    const bpoId = selectedBpo[lineId];
    if (!recipeId || !bpoId) return;
    const tx = buildStartProduction(PACKAGE_IDS.industrial_core, lineId, recipeId, bpoId);
    signAndExecute({ transaction: tx }, {
      onSuccess: () => { invalidate(); addToast("Production started", "ok"); },
      onError: (err: Error) => {
        const match = err.message.match(/MoveAbort.*?(\d+)\)$/);
        addToast(match ? humanError(Number(match[1])) : err.message, "error");
      },
    });
  };

  const handleComplete = (lineId: string) => {
    const tx = buildCompleteProduction(PACKAGE_IDS.industrial_core, lineId);
    signAndExecute({ transaction: tx }, {
      onSuccess: () => { invalidate(); addToast("Production completed", "ok"); },
      onError: (err: Error) => {
        const match = err.message.match(/MoveAbort.*?(\d+)\)$/);
        addToast(match ? humanError(Number(match[1])) : err.message, "error");
      },
    });
  };

  const handleDepositFuel = (lineId: string) => {
    const amt = Number(fuelAmount[lineId] || "0");
    if (amt <= 0) return;
    const tx = buildDepositFuel(PACKAGE_IDS.industrial_core, lineId, amt);
    signAndExecute({ transaction: tx }, {
      onSuccess: () => { invalidate(); addToast("Fuel deposited", "ok"); },
      onError: (err: Error) => {
        const match = err.message.match(/MoveAbort.*?(\d+)\)$/);
        addToast(match ? humanError(Number(match[1])) : err.message, "error");
      },
    });
  };

  if (LINE_IDS.length === 0) {
    return <div className={styles.noLines}>No production line IDs configured</div>;
  }

  return (
    <div className={styles.container}>
      {lines.map((line) => {
        const isRunning = line.status === PRODUCTION_STATUS.RUNNING;
        const isIdle = line.status === PRODUCTION_STATUS.IDLE;
        const now = Date.now();
        const canComplete = isRunning && line.currentJobEnd > 0 && now >= line.currentJobEnd;
        const timeRemaining =
          isRunning && line.currentJobEnd > 0
            ? Math.max(0, line.currentJobEnd - now)
            : 0;

        return (
          <div key={line.id} className={styles.card}>
            <div className={styles.header}>
              <span className={styles.name}>{line.name || truncateAddress(line.id)}</span>
              <StatusBadge
                label={isRunning ? "RUNNING" : "IDLE"}
                variant={isRunning ? "ok" : "muted"}
              />
            </div>

            <div className={styles.stats}>
              <div className={styles.stat}>
                Recipe: <span>{line.recipeId ? truncateAddress(line.recipeId) : "--"}</span>
              </div>
              <div className={styles.stat}>
                Fuel: <span>{line.fuelReserve}</span>
              </div>
              <div className={styles.stat}>
                Jobs: <span>{line.jobsCompleted}</span>
              </div>
            </div>

            {isRunning && timeRemaining > 0 && (
              <>
                <div className={styles.countdown}>
                  Time remaining: {formatDuration(timeRemaining)}
                </div>
                <div className={styles.progressBar}>
                  <div className={styles.progressFill} style={{ width: "50%" }} />
                </div>
              </>
            )}

            <div className={styles.actions}>
              {/* Start Production */}
              {isIdle && (
                <div className={styles.row}>
                  <select
                    className={styles.select}
                    value={selectedRecipe[line.id] ?? ""}
                    onChange={(e) =>
                      setSelectedRecipe((p) => ({ ...p, [line.id]: e.target.value }))
                    }
                  >
                    <option value="">Recipe</option>
                    {recipes.map((r) => (
                      <option key={r.id} value={r.id}>
                        {r.name || truncateAddress(r.id)}
                      </option>
                    ))}
                  </select>
                  <select
                    className={styles.select}
                    value={selectedBpo[line.id] ?? ""}
                    onChange={(e) =>
                      setSelectedBpo((p) => ({ ...p, [line.id]: e.target.value }))
                    }
                  >
                    <option value="">BPO</option>
                    {(bpos.data ?? []).map((b) => (
                      <option key={b.id} value={b.id}>
                        {truncateAddress(b.id)}
                      </option>
                    ))}
                  </select>
                  <button
                    className={styles.btn}
                    disabled={
                      !account ||
                      !selectedRecipe[line.id] ||
                      !selectedBpo[line.id]
                    }
                    onClick={() => handleStart(line.id)}
                  >
                    Start
                  </button>
                </div>
              )}

              {/* Complete Production */}
              {canComplete && (
                <button
                  className={styles.btn}
                  disabled={!account}
                  onClick={() => handleComplete(line.id)}
                >
                  Complete
                </button>
              )}

              {/* Deposit Fuel */}
              <div className={styles.row}>
                <input
                  className={styles.input}
                  type="number"
                  placeholder="Fuel"
                  value={fuelAmount[line.id] ?? ""}
                  onChange={(e) =>
                    setFuelAmount((p) => ({ ...p, [line.id]: e.target.value }))
                  }
                />
                <button
                  className={styles.btn}
                  disabled={!account || !Number(fuelAmount[line.id])}
                  onClick={() => handleDepositFuel(line.id)}
                >
                  Deposit Fuel
                </button>
              </div>
            </div>
          </div>
        );
      })}
    </div>
  );
}
