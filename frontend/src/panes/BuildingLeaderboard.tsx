import { useState } from "react";
import { useBuildingLeaderboard } from "../hooks/useEveEyes";
import styles from "./BuildingLeaderboard.module.css";

const MODULE_TYPES = ["", "assembly", "gate", "network_node", "storage_unit", "turret"] as const;
const MODULE_LABELS: Record<string, string> = {
  "": "All Modules",
  assembly: "Assembly",
  gate: "Gate",
  network_node: "Network Node",
  storage_unit: "Storage Unit",
  turret: "Turret",
};

export function BuildingLeaderboard() {
  const [moduleName, setModuleName] = useState("");
  const [limit, setLimit] = useState(10);

  const { data, isError, isFetching } = useBuildingLeaderboard({
    limit,
    moduleName: moduleName || undefined,
  });

  if (isError) {
    return (
      <div className={styles.container}>
        <div className={styles.unavailable}>Intel Unavailable</div>
      </div>
    );
  }

  const entries = data?.leaderboard ?? [];

  return (
    <div className={styles.container}>
      <div className={styles.filters}>
        <select
          className={styles.select}
          value={moduleName}
          onChange={(e) => setModuleName(e.target.value)}
        >
          {MODULE_TYPES.map((m) => (
            <option key={m} value={m}>
              {MODULE_LABELS[m]}
            </option>
          ))}
        </select>
        <select
          className={styles.select}
          value={limit}
          onChange={(e) => setLimit(Number(e.target.value))}
        >
          <option value={10}>Top 10</option>
          <option value={25}>Top 25</option>
          <option value={50}>Top 50</option>
        </select>
        {isFetching && <span className={styles.refreshing}>updating...</span>}
      </div>

      {entries.length === 0 ? (
        <div className={styles.empty}>No leaderboard data</div>
      ) : (
        <table className={styles.table}>
          <thead>
            <tr>
              <th>#</th>
              <th>Owner</th>
              <th>Wallet</th>
              <th style={{ textAlign: "right" }}>Count</th>
            </tr>
          </thead>
          <tbody>
            {entries.map((entry, i) => (
              <tr key={`${entry.wallet ?? ""}-${i}`}>
                <td className={styles.rank}>{i + 1}</td>
                <td className={styles.owner}>{entry.owner ?? "--"}</td>
                <td className={styles.wallet}>
                  {entry.wallet ? `${entry.wallet.slice(0, 8)}...${entry.wallet.slice(-4)}` : "--"}
                </td>
                <td className={styles.count}>{entry.count ?? 0}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </div>
  );
}
