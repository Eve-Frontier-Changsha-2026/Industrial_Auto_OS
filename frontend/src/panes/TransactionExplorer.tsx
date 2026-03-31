import { Fragment, useState } from "react";
import { useTransactionBlocks, useMoveCallsForTx } from "../hooks/useEveEyes";
import { StatusBadge } from "../components/StatusBadge";
import styles from "./TransactionExplorer.module.css";

function MoveCallsExpander({ digest }: { digest: string }) {
  const { data, isLoading, isError } = useMoveCallsForTx(digest);

  if (isLoading) return <div className={styles.loading}>Loading move calls...</div>;
  if (isError) return <div className={styles.loading}>Failed to load move calls</div>;

  const calls = data?.items ?? [];
  if (calls.length === 0) return <div className={styles.loading}>No move calls</div>;

  return (
    <div className={styles.moveCallsPanel}>
      <div className={styles.moveCallsTitle}>Move Calls ({calls.length})</div>
      {calls.map((mc, i) => (
        <div key={i} className={styles.moveCall}>
          <span className={styles.mcTarget}>
            {mc.moduleName ?? "?"}::{mc.functionName ?? "?"}
          </span>
          {mc.actionSummary && (
            <span className={styles.mcAction}>{mc.actionSummary}</span>
          )}
        </div>
      ))}
    </div>
  );
}

export function TransactionExplorer() {
  const [senderFilter, setSenderFilter] = useState("");
  const [statusFilter, setStatusFilter] = useState("");
  const [digestSearch, setDigestSearch] = useState("");
  const [page, setPage] = useState(1);
  const [expandedDigest, setExpandedDigest] = useState<string | null>(null);

  const { data, isError, isFetching } = useTransactionBlocks({
    page,
    pageSize: 20,
    senderAddress: senderFilter || undefined,
    status: statusFilter || undefined,
    digest: digestSearch || undefined,
  });

  if (isError) {
    return (
      <div className={styles.container}>
        <div className={styles.unavailable}>Intel Unavailable</div>
      </div>
    );
  }

  const txs = data?.items ?? [];
  const hasMore = data?.pagination?.hasMore ?? txs.length === 20;

  return (
    <div className={styles.container}>
      <div className={styles.filters}>
        <input
          className={styles.input}
          placeholder="Sender address..."
          value={senderFilter}
          onChange={(e) => {
            setSenderFilter(e.target.value);
            setPage(1);
          }}
        />
        <input
          className={styles.input}
          placeholder="Digest..."
          value={digestSearch}
          onChange={(e) => {
            setDigestSearch(e.target.value);
            setPage(1);
          }}
        />
        <select
          className={styles.select}
          value={statusFilter}
          onChange={(e) => {
            setStatusFilter(e.target.value);
            setPage(1);
          }}
        >
          <option value="">All</option>
          <option value="success">Success</option>
          <option value="failure">Failure</option>
        </select>
      </div>

      {txs.length === 0 ? (
        <div className={styles.empty}>
          {isFetching ? "Loading..." : "No transactions"}
        </div>
      ) : (
        <table className={styles.table}>
          <thead>
            <tr>
              <th>Digest</th>
              <th>Sender</th>
              <th>Status</th>
              <th>Kind</th>
              <th>Time</th>
            </tr>
          </thead>
          <tbody>
            {txs.map((tx) => (
              <Fragment key={tx.digest}>
                <tr
                  onClick={() =>
                    setExpandedDigest(
                      expandedDigest === tx.digest ? null : tx.digest,
                    )
                  }
                >
                  <td className={styles.digest}>
                    {tx.digest?.slice(0, 12)}...
                  </td>
                  <td className={styles.sender}>
                    {tx.sender
                      ? `${tx.sender.slice(0, 8)}...${tx.sender.slice(-4)}`
                      : "--"}
                  </td>
                  <td>
                    <StatusBadge
                      label={tx.status ?? "unknown"}
                      variant={tx.status === "success" ? "ok" : "error"}
                    />
                  </td>
                  <td>{tx.transactionKind ?? "--"}</td>
                  <td>
                    {tx.transactionTime
                      ? new Date(tx.transactionTime).toLocaleString(undefined, {
                          month: "short",
                          day: "numeric",
                          hour: "2-digit",
                          minute: "2-digit",
                        })
                      : "--"}
                  </td>
                </tr>
                {expandedDigest === tx.digest && (
                  <tr className={styles.expandedRow}>
                    <td colSpan={5}>
                      <MoveCallsExpander digest={tx.digest} />
                    </td>
                  </tr>
                )}
              </Fragment>
            ))}
          </tbody>
        </table>
      )}

      <div className={styles.pagination}>
        <button
          className={styles.pageBtn}
          disabled={page <= 1}
          onClick={() => setPage((p) => p - 1)}
        >
          Prev
        </button>
        <span className={styles.pageInfo}>Page {page}</span>
        <button
          className={styles.pageBtn}
          disabled={!hasMore}
          onClick={() => setPage((p) => p + 1)}
        >
          Next
        </button>
      </div>
    </div>
  );
}
