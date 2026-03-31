import { useState } from "react";
import { useKillmails } from "../hooks/useEveEyes";
import styles from "./KillmailFeed.module.css";

export function KillmailFeed() {
  const [statusFilter, setStatusFilter] = useState("");
  const [limit, setLimit] = useState(20);

  const { data, isError, isFetching } = useKillmails({
    limit,
    status: statusFilter || undefined,
  });

  if (isError) {
    return (
      <div className={styles.container}>
        <div className={styles.unavailable}>Intel Unavailable</div>
      </div>
    );
  }

  const killmails = data?.items ?? [];

  return (
    <div className={styles.container}>
      <div className={styles.filters}>
        <select
          className={styles.select}
          value={statusFilter}
          onChange={(e) => setStatusFilter(e.target.value)}
        >
          <option value="">All Status</option>
          <option value="resolved">Resolved</option>
          <option value="pending">Pending</option>
        </select>
        <select
          className={styles.select}
          value={limit}
          onChange={(e) => setLimit(Number(e.target.value))}
        >
          <option value={10}>10</option>
          <option value={20}>20</option>
          <option value={50}>50</option>
        </select>
        {isFetching && <span className={styles.refreshing}>updating...</span>}
      </div>

      {killmails.length === 0 ? (
        <div className={styles.empty}>No killmails</div>
      ) : (
        <div className={styles.list}>
          {killmails.map((km, i) => (
            <div key={`${km.killmailItemId}-${i}`} className={styles.row}>
              <span className={styles.timestamp}>
                {km.killTimestamp
                  ? new Date(km.killTimestamp).toLocaleString(undefined, {
                      month: "short",
                      day: "numeric",
                      hour: "2-digit",
                      minute: "2-digit",
                      second: "2-digit",
                    })
                  : "--"}
              </span>
              <span className={styles.killer}>{km.killer?.label ?? "Unknown"}</span>
              <span className={styles.vs}>destroyed</span>
              <span className={styles.victim}>{km.victim?.label ?? "Unknown"}</span>
              {km.status && (
                <span
                  className={`${styles.statusTag} ${
                    km.status === "resolved" ? styles.statusResolved : styles.statusPending
                  }`}
                >
                  {km.status}
                </span>
              )}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
