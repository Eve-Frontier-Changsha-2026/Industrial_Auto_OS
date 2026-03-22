import { useState } from "react";
import { useWorkOrders } from "../hooks/useWorkOrders";
import { truncateAddress, formatSui, formatTimestamp } from "../lib/format";
import { ORDER_STATUS, ORDER_STATUS_LABEL, ORDER_PRIORITY_LABEL } from "../lib/types";
import { StatusBadge } from "../components/StatusBadge";
import styles from "./WorkOrderBoard.module.css";

const STATUS_VARIANT: Record<number, "ok" | "warn" | "error" | "info"> = {
  [ORDER_STATUS.OPEN]: "info",
  [ORDER_STATUS.ACCEPTED]: "warn",
  [ORDER_STATUS.DELIVERING]: "warn",
  [ORDER_STATUS.DELIVERED]: "ok",
  [ORDER_STATUS.COMPLETED]: "ok",
  [ORDER_STATUS.CANCELLED]: "error",
};

const TABS = [
  { label: "All", value: -1 },
  { label: "Open", value: ORDER_STATUS.OPEN },
  { label: "Accepted", value: ORDER_STATUS.ACCEPTED },
  { label: "Delivering", value: ORDER_STATUS.DELIVERING },
  { label: "Delivered", value: ORDER_STATUS.DELIVERED },
  { label: "Completed", value: ORDER_STATUS.COMPLETED },
  { label: "Cancelled", value: ORDER_STATUS.CANCELLED },
];

export function WorkOrderBoard() {
  const { data: orders, isLoading } = useWorkOrders();
  const [statusFilter, setStatusFilter] = useState(-1);
  const [selectedOrderId, setSelectedOrderId] = useState<string | null>(null);

  const filtered =
    statusFilter === -1
      ? orders ?? []
      : (orders ?? []).filter((o) => o.status === statusFilter);

  return (
    <div className={styles.container}>
      <div className={styles.tabs}>
        {TABS.map((t) => (
          <button
            key={t.value}
            className={`${styles.tab} ${statusFilter === t.value ? styles.tabActive : ""}`}
            onClick={() => setStatusFilter(t.value)}
          >
            {t.label}
          </button>
        ))}
      </div>

      {isLoading ? (
        <div className={styles.empty}>Loading...</div>
      ) : !filtered.length ? (
        <div className={styles.empty}>No work orders found</div>
      ) : (
        <table className={styles.table}>
          <thead>
            <tr>
              <th>ID</th>
              <th>Description</th>
              <th>Recipe</th>
              <th>Qty</th>
              <th>Escrow</th>
              <th>Deadline</th>
              <th>Status</th>
              <th>Priority</th>
            </tr>
          </thead>
          <tbody>
            {filtered.map((order) => (
              <tr
                key={order.id}
                className={selectedOrderId === order.id ? styles.selected : ""}
                onClick={() => setSelectedOrderId(order.id)}
              >
                <td>{truncateAddress(order.id)}</td>
                <td className={styles.desc}>
                  {order.description.length > 30
                    ? order.description.slice(0, 30) + "..."
                    : order.description}
                </td>
                <td>{truncateAddress(order.recipeId)}</td>
                <td>
                  {order.quantityDelivered}/{order.quantityRequired}
                </td>
                <td>{formatSui(order.escrowValue)}</td>
                <td>{formatTimestamp(order.deadline)}</td>
                <td>
                  <StatusBadge
                    label={ORDER_STATUS_LABEL[order.status] ?? "Unknown"}
                    variant={STATUS_VARIANT[order.status] ?? "muted"}
                  />
                </td>
                <td>{ORDER_PRIORITY_LABEL[order.priority] ?? "?"}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </div>
  );
}
