import { useState } from "react";
import { useSignAndExecuteTransaction, useCurrentAccount } from "@mysten/dapp-kit";
import { useQueryClient } from "@tanstack/react-query";
import { useLeases } from "../hooks/useLeases";
import { useBlueprints } from "../hooks/useBlueprints";
import { formatSui, formatTimestamp, formatDuration, truncateAddress, isValidSuiId } from "../lib/format";
import { PACKAGE_IDS } from "../lib/constants";
import { useToast } from "../hooks/useToast";
import { humanError } from "../lib/errors";
import { StatusBadge } from "../components/StatusBadge";
import { buildCreateLease, buildReturnLease, buildForfeitLease } from "../lib/ptb/lease";
import styles from "./LeaseManager.module.css";

export function LeaseManager() {
  const account = useCurrentAccount();
  const queryClient = useQueryClient();
  const { mutate: signAndExecute } = useSignAndExecuteTransaction();
  const { addToast } = useToast();
  const { data: leases = [] } = useLeases();
  const { bpos } = useBlueprints();

  const [showForm, setShowForm] = useState(false);
  const [bpoId, setBpoId] = useState("");
  const [lessee, setLessee] = useState("");
  const [deposit, setDeposit] = useState("");
  const [expiryDays, setExpiryDays] = useState("");
  const [dailyRate, setDailyRate] = useState("");

  const addr = account?.address ?? "";
  const pkg = PACKAGE_IDS.marketplace;

  function handleReturn(leaseId: string) {
    const tx = buildReturnLease(pkg, leaseId);
    signAndExecute({ transaction: tx }, {
      onSuccess: () => {
        queryClient.invalidateQueries({ queryKey: ["leases"] });
        addToast("Lease returned", "ok");
      },
      onError: (err: Error) => {
        const match = err.message.match(/MoveAbort.*?(\d+)\)$/);
        addToast(match ? humanError(Number(match[1])) : err.message, "error");
      },
    });
  }

  function handleForfeit(leaseId: string) {
    const tx = buildForfeitLease(pkg, leaseId);
    signAndExecute({ transaction: tx }, {
      onSuccess: () => {
        queryClient.invalidateQueries({ queryKey: ["leases"] });
        addToast("Lease forfeited", "ok");
      },
      onError: (err: Error) => {
        const match = err.message.match(/MoveAbort.*?(\d+)\)$/);
        addToast(match ? humanError(Number(match[1])) : err.message, "error");
      },
    });
  }

  function handleCreate() {
    if (!bpoId || !lessee || !deposit || !expiryDays || !dailyRate) return;
    if (!isValidSuiId(lessee)) {
      addToast("Invalid lessee address (expected 0x...)", "error");
      return;
    }
    const depositMist = BigInt(Math.floor(Number(deposit) * 1e9));
    const expiryMs = Date.now() + Number(expiryDays) * 86_400_000;
    const tx = buildCreateLease(pkg, bpoId, lessee, depositMist, expiryMs, Number(dailyRate));
    signAndExecute({ transaction: tx }, {
      onSuccess: () => {
        queryClient.invalidateQueries({ queryKey: ["leases"] });
        setBpoId("");
        setLessee("");
        setDeposit("");
        setExpiryDays("");
        setDailyRate("");
        setShowForm(false);
        addToast("Lease created", "ok");
      },
      onError: (err: Error) => {
        const match = err.message.match(/MoveAbort.*?(\d+)\)$/);
        addToast(match ? humanError(Number(match[1])) : err.message, "error");
      },
    });
  }

  const now = Date.now();

  return (
    <div className={styles.container}>
      {leases.length === 0 ? (
        <div className={styles.empty}>No leases</div>
      ) : (
        <table className={styles.table}>
          <thead>
            <tr>
              <th>ID</th>
              <th>Lessor</th>
              <th>Lessee</th>
              <th>Daily Rate</th>
              <th>Deposit</th>
              <th>Expiry</th>
              <th>Status</th>
              <th>Actions</th>
            </tr>
          </thead>
          <tbody>
            {leases.map((l) => {
              const expired = l.expiry < now;
              const isLessee = l.lessee === addr;
              const isLessor = l.lessor === addr;
              return (
                <tr key={l.id}>
                  <td>{truncateAddress(l.id)}</td>
                  <td>{truncateAddress(l.lessor)}</td>
                  <td>{truncateAddress(l.lessee)}</td>
                  <td>{formatSui(l.dailyRate)} SUI</td>
                  <td>{formatSui(l.depositValue)} SUI</td>
                  <td>
                    {formatTimestamp(l.expiry)}
                    {l.active && !expired && (
                      <div className={styles.countdown}>{formatDuration(l.expiry - now)}</div>
                    )}
                  </td>
                  <td>
                    <StatusBadge
                      label={l.active ? (expired ? "Expired" : "Active") : "Closed"}
                      variant={l.active ? (expired ? "warn" : "ok") : "muted"}
                    />
                  </td>
                  <td>
                    {l.active && isLessee && !expired && (
                      <button className={styles.btn} onClick={() => handleReturn(l.id)} disabled={!account}>
                        Return
                      </button>
                    )}
                    {l.active && isLessor && expired && (
                      <button
                        className={`${styles.btn} ${styles.btnDanger}`}
                        onClick={() => handleForfeit(l.id)}
                        disabled={!account}
                      >
                        Forfeit
                      </button>
                    )}
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      )}

      <div className={styles.createForm}>
        <div className={styles.formTitle} onClick={() => setShowForm(!showForm)}>
          {showForm ? "- Hide" : "+ Create Lease"}
        </div>
        {showForm && (
          <>
            <div className={styles.formRow}>
              <span className={styles.label}>BPO</span>
              <select className={styles.select} value={bpoId} onChange={(e) => setBpoId(e.target.value)} disabled={!account}>
                <option value="">Select BPO</option>
                {(bpos.data ?? []).map((b) => (
                  <option key={b.id} value={b.id}>{truncateAddress(b.id)}</option>
                ))}
              </select>
            </div>
            <div className={styles.formRow}>
              <span className={styles.label}>Lessee</span>
              <input className={styles.input} placeholder="0x..." value={lessee} onChange={(e) => setLessee(e.target.value)} disabled={!account} />
            </div>
            <div className={styles.formRow}>
              <span className={styles.label}>Deposit (SUI)</span>
              <input className={styles.input} type="number" placeholder="0" value={deposit} onChange={(e) => setDeposit(e.target.value)} disabled={!account} />
            </div>
            <div className={styles.formRow}>
              <span className={styles.label}>Expiry (days)</span>
              <input className={styles.input} type="number" placeholder="7" value={expiryDays} onChange={(e) => setExpiryDays(e.target.value)} disabled={!account} />
            </div>
            <div className={styles.formRow}>
              <span className={styles.label}>Daily Rate (MIST)</span>
              <input className={styles.input} type="number" placeholder="100000000" value={dailyRate} onChange={(e) => setDailyRate(e.target.value)} disabled={!account} />
            </div>
            <button className={styles.btn} onClick={handleCreate} disabled={!account || !bpoId || !lessee || !deposit || !expiryDays || !dailyRate}>
              Create Lease
            </button>
          </>
        )}
      </div>
    </div>
  );
}
