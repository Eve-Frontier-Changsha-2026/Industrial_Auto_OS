import { useState } from "react";
import { useWatcherTxLog, useWatcherStatus } from "../hooks/useWatcher";
import { formatTimestamp } from "../lib/format";
import { StatusBadge } from "../components/StatusBadge";
import styles from "./TxLog.module.css";

export function TxLog() {
  const [statusFilter, setStatusFilter] = useState("");
  const [ruleFilter, setRuleFilter] = useState("");

  const { data: statusData, isError: statusError } = useWatcherStatus();
  const { data: txData, isError: txError } = useWatcherTxLog({
    status: statusFilter || undefined,
    rule: ruleFilter || undefined,
    limit: 100,
  });

  if (statusError || txError) {
    return (
      <div className={styles.container}>
        <div className={styles.offline}>Watcher Offline</div>
      </div>
    );
  }

  const transactions = txData?.transactions ?? [];
  const ruleNames = (statusData?.rules ?? []).map((r) => r.name);

  return (
    <div className={styles.container}>
      <div className={styles.filters}>
        <select className={styles.select} value={statusFilter} onChange={(e) => setStatusFilter(e.target.value)}>
          <option value="">All Status</option>
          <option value="success">Success</option>
          <option value="error">Error</option>
        </select>
        <select className={styles.select} value={ruleFilter} onChange={(e) => setRuleFilter(e.target.value)}>
          <option value="">All Rules</option>
          {ruleNames.map((name) => (
            <option key={name} value={name}>{name}</option>
          ))}
        </select>
      </div>

      {transactions.length === 0 ? (
        <div className={styles.empty}>No transactions</div>
      ) : (
        <table className={styles.table}>
          <thead>
            <tr>
              <th>Time</th>
              <th>TX Digest</th>
              <th>Status</th>
              <th>Gas</th>
              <th>Rule</th>
            </tr>
          </thead>
          <tbody>
            {transactions.map((tx, i) => (
              <tr key={`${tx.tx_digest}-${i}`}>
                <td>{formatTimestamp(tx.created_at)}</td>
                <td className={styles.digest}>{tx.tx_digest.slice(0, 10)}...</td>
                <td>
                  <StatusBadge
                    label={tx.status}
                    variant={tx.status === "success" ? "ok" : "error"}
                  />
                </td>
                <td>{tx.gas_used}</td>
                <td>
                  {tx.rule_name}
                  {tx.error && <div className={styles.error}>{tx.error}</div>}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </div>
  );
}
