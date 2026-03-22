import { useProductionLines } from "../hooks/useProductionLines";
import { useWorkOrders } from "../hooks/useWorkOrders";
import { PRODUCTION_STATUS, ORDER_STATUS } from "../lib/types";
import styles from "./SystemOverview.module.css";

const LINE_IDS = (import.meta.env.VITE_PRODUCTION_LINE_IDS ?? "")
  .split(",")
  .filter(Boolean);

export function SystemOverview() {
  const { data: lines = [] } = useProductionLines(LINE_IDS);
  const { data: orders = [] } = useWorkOrders();

  const activeJobs = lines.filter((l) => l.status === PRODUCTION_STATUS.RUNNING).length;
  const totalFuel = lines.reduce((s, l) => s + l.fuelReserve, 0);
  const totalJobs = lines.reduce((s, l) => s + l.jobsCompleted, 0);
  const openOrders = orders.filter((o) => o.status === ORDER_STATUS.OPEN).length;
  const completedOrders = orders.filter((o) => o.status === ORDER_STATUS.COMPLETED).length;

  const cards = [
    { label: "Production Lines", value: lines.length },
    { label: "Active Jobs", value: activeJobs },
    { label: "Open Orders", value: openOrders },
    { label: "Completed Orders", value: completedOrders },
    { label: "Total Jobs", value: totalJobs },
    { label: "Fuel Reserve", value: totalFuel },
  ];

  return (
    <div className={styles.grid}>
      {cards.map((c) => (
        <div key={c.label} className={styles.card}>
          <div className={styles.value}>{c.value}</div>
          <div className={styles.label}>{c.label}</div>
        </div>
      ))}
    </div>
  );
}
