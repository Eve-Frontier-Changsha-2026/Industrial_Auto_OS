import { useState } from "react";
import {
  useCurrentAccount,
  useSignAndExecuteTransaction,
} from "@mysten/dapp-kit";
import { useQueryClient } from "@tanstack/react-query";
import { useRecipes } from "../hooks/useRecipes";
import { useToast } from "../hooks/useToast";
import { humanError } from "../lib/errors";
import { PACKAGE_IDS } from "../lib/constants";
import { truncateAddress } from "../lib/format";
import {
  buildDepositMaterials,
  buildWithdrawOutput,
} from "../lib/ptb/production";
import styles from "./MaterialInventory.module.css";

const LINE_IDS = (import.meta.env.VITE_PRODUCTION_LINE_IDS ?? "")
  .split(",")
  .filter(Boolean);

export function MaterialInventory() {
  const account = useCurrentAccount();
  const { mutate: signAndExecute } = useSignAndExecuteTransaction();
  const queryClient = useQueryClient();
  const { addToast } = useToast();
  const { data: recipes = [] } = useRecipes();

  const [selectedLine, setSelectedLine] = useState(LINE_IDS[0] ?? "");
  const [selectedRecipe, setSelectedRecipe] = useState("");
  const [depItemType, setDepItemType] = useState("");
  const [depQty, setDepQty] = useState("");
  const [withItemType, setWithItemType] = useState("");
  const [withQty, setWithQty] = useState("");

  const invalidate = () =>
    queryClient.invalidateQueries({ queryKey: ["production-lines"] });

  const handleDeposit = () => {
    if (!selectedLine || !selectedRecipe || !depItemType || !depQty) return;
    const tx = buildDepositMaterials(
      PACKAGE_IDS.industrial_core,
      selectedLine,
      selectedRecipe,
      Number(depItemType),
      Number(depQty),
    );
    signAndExecute({ transaction: tx }, {
      onSuccess: () => { invalidate(); addToast("Materials deposited", "ok"); },
      onError: (err: Error) => {
        const match = err.message.match(/MoveAbort.*?(\d+)\)$/);
        addToast(match ? humanError(Number(match[1])) : err.message, "error");
      },
    });
  };

  const handleWithdraw = () => {
    if (!selectedLine || !withItemType || !withQty) return;
    const tx = buildWithdrawOutput(
      PACKAGE_IDS.industrial_core,
      selectedLine,
      Number(withItemType),
      Number(withQty),
    );
    signAndExecute({ transaction: tx }, {
      onSuccess: () => { invalidate(); addToast("Output withdrawn", "ok"); },
      onError: (err: Error) => {
        const match = err.message.match(/MoveAbort.*?(\d+)\)$/);
        addToast(match ? humanError(Number(match[1])) : err.message, "error");
      },
    });
  };

  if (!account) {
    return <div className={styles.noWallet}>Connect wallet to manage materials</div>;
  }

  return (
    <div className={styles.container}>
      {/* Line selector */}
      <div className={styles.form}>
        <span className={styles.label}>Line:</span>
        <select
          className={styles.select}
          value={selectedLine}
          onChange={(e) => setSelectedLine(e.target.value)}
        >
          {LINE_IDS.map((id: string) => (
            <option key={id} value={id}>
              {truncateAddress(id)}
            </option>
          ))}
        </select>
      </div>

      {/* Deposit Materials */}
      <div className={styles.section}>
        <div className={styles.sectionTitle}>Deposit Materials</div>
        <div className={styles.form}>
          <select
            className={styles.select}
            value={selectedRecipe}
            onChange={(e) => setSelectedRecipe(e.target.value)}
          >
            <option value="">Recipe</option>
            {recipes.map((r) => (
              <option key={r.id} value={r.id}>
                {r.name || truncateAddress(r.id)}
              </option>
            ))}
          </select>
          <input
            className={styles.input}
            type="number"
            placeholder="Item Type"
            value={depItemType}
            onChange={(e) => setDepItemType(e.target.value)}
          />
          <input
            className={styles.input}
            type="number"
            placeholder="Qty"
            value={depQty}
            onChange={(e) => setDepQty(e.target.value)}
          />
          <button
            className={styles.btn}
            disabled={!selectedRecipe || !depItemType || !depQty}
            onClick={handleDeposit}
          >
            Deposit
          </button>
        </div>
      </div>

      {/* Withdraw Output */}
      <div className={styles.section}>
        <div className={styles.sectionTitle}>Withdraw Output</div>
        <div className={styles.form}>
          <input
            className={styles.input}
            type="number"
            placeholder="Item Type"
            value={withItemType}
            onChange={(e) => setWithItemType(e.target.value)}
          />
          <input
            className={styles.input}
            type="number"
            placeholder="Qty"
            value={withQty}
            onChange={(e) => setWithQty(e.target.value)}
          />
          <button
            className={styles.btn}
            disabled={!withItemType || !withQty}
            onClick={handleWithdraw}
          >
            Withdraw
          </button>
        </div>
      </div>
    </div>
  );
}
