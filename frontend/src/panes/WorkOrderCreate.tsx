import { useState } from "react";
import { useSignAndExecuteTransaction, useCurrentAccount } from "@mysten/dapp-kit";
import { useQueryClient } from "@tanstack/react-query";
import { useRecipes } from "../hooks/useRecipes";
import { PACKAGE_IDS, SHARED_OBJECTS } from "../lib/constants";
import { buildCreateWorkOrder, buildCreateOrderFromDamageReport } from "../lib/ptb/workOrder";
import { useToast } from "../hooks/useToast";
import { humanError } from "../lib/errors";
import styles from "./WorkOrderCreate.module.css";

export function WorkOrderCreate() {
  const account = useCurrentAccount();
  const queryClient = useQueryClient();
  const { data: recipes } = useRecipes();
  const { mutate: signAndExecute } = useSignAndExecuteTransaction();
  const { addToast } = useToast();

  const [description, setDescription] = useState("");
  const [recipeId, setRecipeId] = useState("");
  const [quantity, setQuantity] = useState(1);
  const [escrow, setEscrow] = useState(0);
  const [deadlineDays, setDeadlineDays] = useState(7);
  const [priority, setPriority] = useState(1);
  const [sourceEvent, setSourceEvent] = useState("");

  if (!account) {
    return <div className={styles.empty}>Connect wallet to create work orders</div>;
  }

  const canSubmit = description.trim() && recipeId && quantity > 0 && escrow > 0 && deadlineDays > 0;

  function handleSubmit() {
    if (!canSubmit) return;

    const deadlineMs = Date.now() + deadlineDays * 24 * 60 * 60 * 1000;
    const escrowMist = BigInt(Math.round(escrow * 1e9));

    const tx = sourceEvent.trim()
      ? buildCreateOrderFromDamageReport(
          PACKAGE_IDS.work_order,
          SHARED_OBJECTS.work_order_board,
          description,
          recipeId,
          quantity,
          escrowMist,
          deadlineMs,
          sourceEvent.trim(),
        )
      : buildCreateWorkOrder(
          PACKAGE_IDS.work_order,
          SHARED_OBJECTS.work_order_board,
          description,
          recipeId,
          quantity,
          escrowMist,
          deadlineMs,
          priority,
        );

    signAndExecute(
      { transaction: tx },
      {
        onSuccess: () => {
          queryClient.invalidateQueries({ queryKey: ["work-orders"] });
          addToast("Work order created", "ok");
          setDescription("");
          setRecipeId("");
          setQuantity(1);
          setEscrow(0);
          setDeadlineDays(7);
          setPriority(1);
          setSourceEvent("");
        },
        onError: (err: Error) => {
          const match = err.message.match(/MoveAbort.*?(\d+)\)$/);
          addToast(match ? humanError(Number(match[1])) : err.message, "error");
        },
      },
    );
  }

  return (
    <div className={styles.container}>
      <div className={styles.field}>
        <label className={styles.label}>Description</label>
        <input
          className={styles.input}
          type="text"
          value={description}
          onChange={(e) => setDescription(e.target.value)}
          placeholder="Work order description"
        />
      </div>

      <div className={styles.field}>
        <label className={styles.label}>Recipe</label>
        <select
          className={styles.select}
          value={recipeId}
          onChange={(e) => setRecipeId(e.target.value)}
        >
          <option value="">-- Select Recipe --</option>
          {(recipes ?? []).map((r) => (
            <option key={r.id} value={r.id}>
              {r.name}
            </option>
          ))}
        </select>
      </div>

      <div className={styles.field}>
        <label className={styles.label}>Quantity</label>
        <input
          className={styles.input}
          type="number"
          min={1}
          value={quantity}
          onChange={(e) => setQuantity(Math.max(1, Number(e.target.value)))}
        />
      </div>

      <div className={styles.field}>
        <label className={styles.label}>Escrow (SUI)</label>
        <input
          className={styles.input}
          type="number"
          min={0}
          step={0.01}
          value={escrow}
          onChange={(e) => setEscrow(Math.max(0, Number(e.target.value)))}
        />
      </div>

      <div className={styles.field}>
        <label className={styles.label}>Deadline (days from now)</label>
        <input
          className={styles.input}
          type="number"
          min={1}
          value={deadlineDays}
          onChange={(e) => setDeadlineDays(Math.max(1, Number(e.target.value)))}
        />
        <span className={styles.hint}>Converted to on-chain timestamp</span>
      </div>

      <div className={styles.field}>
        <label className={styles.label}>Priority</label>
        <select
          className={styles.select}
          value={priority}
          onChange={(e) => setPriority(Number(e.target.value))}
        >
          <option value={0}>Low</option>
          <option value={1}>Normal</option>
          <option value={2}>High</option>
          <option value={3}>Critical</option>
        </select>
      </div>

      <div className={styles.field}>
        <label className={styles.label}>Source Event (optional)</label>
        <input
          className={styles.input}
          type="text"
          value={sourceEvent}
          onChange={(e) => setSourceEvent(e.target.value)}
          placeholder="Damage report event ID"
        />
        <span className={styles.hint}>If set, creates order via fleet_integration</span>
      </div>

      <button className={styles.btn} disabled={!canSubmit} onClick={handleSubmit}>
        Create Work Order
      </button>
    </div>
  );
}
