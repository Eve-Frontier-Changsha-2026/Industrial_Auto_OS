import { useState } from "react";
import { useSignAndExecuteTransaction, useCurrentAccount } from "@mysten/dapp-kit";
import { useQueryClient } from "@tanstack/react-query";
import { useTriggers } from "../hooks/useTriggers";
import { useProductionLines } from "../hooks/useProductionLines";
import { formatTimestamp, formatDuration, truncateAddress } from "../lib/format";
import { PACKAGE_IDS } from "../lib/constants";
import { useToast } from "../hooks/useToast";
import { humanError } from "../lib/errors";
import { TRIGGER_CONDITION } from "../lib/types";
import { StatusBadge } from "../components/StatusBadge";
import { buildCreateTriggerRule, buildToggleTrigger } from "../lib/ptb/triggerEngine";
import styles from "./TriggerEngine.module.css";

const CONDITION_LABELS: Record<number, string> = {
  [TRIGGER_CONDITION.OUTPUT_BUFFER_ABOVE]: "OUTPUT_BUFFER_ABOVE",
  [TRIGGER_CONDITION.INPUT_BUFFER_BELOW]: "INPUT_BUFFER_BELOW",
  [TRIGGER_CONDITION.FUEL_BELOW]: "FUEL_BELOW",
};

const LINE_IDS = (import.meta.env.VITE_PRODUCTION_LINE_IDS ?? "")
  .split(",")
  .filter(Boolean);

export function TriggerEngine() {
  const account = useCurrentAccount();
  const queryClient = useQueryClient();
  const { mutate: signAndExecute } = useSignAndExecuteTransaction();
  const { addToast } = useToast();
  const { data: triggers = [] } = useTriggers();
  const { data: lines = [] } = useProductionLines(LINE_IDS);

  // create form state
  const [lineId, setLineId] = useState("");
  const [conditionType, setConditionType] = useState(0);
  const [threshold, setThreshold] = useState("");
  const [targetItemTypeId, setTargetItemTypeId] = useState("");
  const [autoRepeat, setAutoRepeat] = useState(false);
  const [cooldownSec, setCooldownSec] = useState("");

  const pkg = PACKAGE_IDS.industrial_core;

  function handleToggle(ruleId: string, currentEnabled: boolean) {
    const tx = buildToggleTrigger(pkg, ruleId, !currentEnabled);
    signAndExecute({ transaction: tx }, {
      onSuccess: () => {
        queryClient.invalidateQueries({ queryKey: ["triggers"] });
        addToast(`Trigger ${currentEnabled ? "disabled" : "enabled"}`, "ok");
      },
      onError: (err: Error) => {
        const match = err.message.match(/MoveAbort.*?(\d+)\)$/);
        addToast(match ? humanError(Number(match[1])) : err.message, "error");
      },
    });
  }

  function handleCreate() {
    if (!lineId || !threshold || !targetItemTypeId) return;
    const cooldownMs = Number(cooldownSec || 0) * 1000;
    const tx = buildCreateTriggerRule(
      pkg, lineId, conditionType, Number(threshold),
      Number(targetItemTypeId), autoRepeat, cooldownMs,
    );
    signAndExecute({ transaction: tx }, {
      onSuccess: () => {
        queryClient.invalidateQueries({ queryKey: ["triggers"] });
        setLineId("");
        setConditionType(0);
        setThreshold("");
        setTargetItemTypeId("");
        setAutoRepeat(false);
        setCooldownSec("");
        addToast("Trigger rule created", "ok");
      },
      onError: (err: Error) => {
        const match = err.message.match(/MoveAbort.*?(\d+)\)$/);
        addToast(match ? humanError(Number(match[1])) : err.message, "error");
      },
    });
  }

  return (
    <div className={styles.container}>
      {/* Active rules */}
      <div className={styles.section}>
        <div className={styles.sectionTitle}>Active Rules</div>
        <div className={styles.rules}>
          {triggers.length === 0 && <div className={styles.empty}>No trigger rules</div>}
          {triggers.map((t) => (
            <div key={t.id} className={styles.rule}>
              <div className={styles.ruleInfo}>
                <span className={styles.ruleCondition}>
                  {CONDITION_LABELS[t.conditionType] ?? `TYPE_${t.conditionType}`}
                  {" >= "}{t.threshold}
                </span>
                <span className={styles.ruleDetail}>
                  Line: {truncateAddress(t.productionLineId)} | Target: {t.targetItemTypeId} |
                  Cooldown: {formatDuration(t.cooldownMs)} |
                  {t.autoRepeat ? " Repeat" : " Once"} |
                  Last: {t.lastTriggered ? formatTimestamp(t.lastTriggered) : "never"}
                </span>
              </div>
              <div className={styles.ruleActions}>
                <StatusBadge
                  label={t.enabled ? "ON" : "OFF"}
                  variant={t.enabled ? "ok" : "muted"}
                />
                <button
                  className={styles.toggleBtn}
                  onClick={() => handleToggle(t.id, t.enabled)}
                  disabled={!account}
                >
                  {t.enabled ? "Disable" : "Enable"}
                </button>
              </div>
            </div>
          ))}
        </div>
      </div>

      {/* Create form */}
      <div className={styles.section}>
        <div className={styles.sectionTitle}>Create Rule</div>
        <div className={styles.form}>
          <div className={styles.formRow}>
            <span className={styles.label}>Line</span>
            <select className={styles.select} value={lineId} onChange={(e) => setLineId(e.target.value)} disabled={!account}>
              <option value="">Select Line</option>
              {lines.map((l) => (
                <option key={l.id} value={l.id}>{l.name || truncateAddress(l.id)}</option>
              ))}
              {LINE_IDS.filter((id: string) => !lines.find((l) => l.id === id)).map((id: string) => (
                <option key={id} value={id}>{truncateAddress(id)}</option>
              ))}
            </select>
          </div>
          <div className={styles.formRow}>
            <span className={styles.label}>Condition</span>
            <select className={styles.select} value={conditionType} onChange={(e) => setConditionType(Number(e.target.value))} disabled={!account}>
              <option value={0}>OUTPUT_BUFFER_ABOVE</option>
              <option value={1}>INPUT_BUFFER_BELOW</option>
              <option value={2}>FUEL_BELOW</option>
            </select>
          </div>
          <div className={styles.formRow}>
            <span className={styles.label}>Threshold</span>
            <input className={styles.input} type="number" placeholder="100" value={threshold} onChange={(e) => setThreshold(e.target.value)} disabled={!account} />
          </div>
          <div className={styles.formRow}>
            <span className={styles.label}>Target Item</span>
            <input className={styles.input} type="number" placeholder="Item Type ID" value={targetItemTypeId} onChange={(e) => setTargetItemTypeId(e.target.value)} disabled={!account} />
          </div>
          <div className={styles.formRow}>
            <span className={styles.label}>Auto Repeat</span>
            <input className={styles.checkbox} type="checkbox" checked={autoRepeat} onChange={(e) => setAutoRepeat(e.target.checked)} disabled={!account} />
          </div>
          <div className={styles.formRow}>
            <span className={styles.label}>Cooldown (sec)</span>
            <input className={styles.input} type="number" placeholder="60" value={cooldownSec} onChange={(e) => setCooldownSec(e.target.value)} disabled={!account} />
          </div>
          <button className={styles.btn} onClick={handleCreate} disabled={!account || !lineId || !threshold || !targetItemTypeId}>
            Create Rule
          </button>
        </div>
      </div>
    </div>
  );
}
