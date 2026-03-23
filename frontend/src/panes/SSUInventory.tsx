import { StatusBadge } from "../components/StatusBadge";
import styles from "./SSUInventory.module.css";

const MOCK_ITEMS = [
  { eveTypeId: "34", name: "Tritanium", qty: 12_500, mapped: true },
  { eveTypeId: "35", name: "Pyerite", qty: 4_800, mapped: true },
  { eveTypeId: "36", name: "Mexallon", qty: 920, mapped: false },
];

export function SSUInventory() {
  return (
    <div className={styles.container}>
      <div className={styles.section}>
        <div className={styles.sectionTitle}>SSU Connection</div>
        <div className={styles.info}>
          <StatusBadge label="Pending" variant="warn" />{" "}
          SSU integration pending EVE world contracts. Items will appear once an SSU is linked.
        </div>
      </div>

      <div className={styles.section}>
        <div className={styles.sectionTitle}>Preview (mock data)</div>
        <div className={styles.muted}>
          The table below shows what SSU inventory will look like once connected.
        </div>
        <table className={styles.table}>
          <thead>
            <tr>
              <th>EVE Type</th>
              <th>Name</th>
              <th>Quantity</th>
              <th>Mapped</th>
            </tr>
          </thead>
          <tbody>
            {MOCK_ITEMS.map((item) => (
              <tr key={item.eveTypeId}>
                <td>{item.eveTypeId}</td>
                <td>{item.name}</td>
                <td>{item.qty.toLocaleString()}</td>
                <td>
                  <StatusBadge
                    label={item.mapped ? "Yes" : "No"}
                    variant={item.mapped ? "ok" : "muted"}
                  />
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
