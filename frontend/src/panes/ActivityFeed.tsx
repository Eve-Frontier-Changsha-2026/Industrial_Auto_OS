import { useEvents } from "../hooks/useEvents";
import { formatTimestamp } from "../lib/format";
import styles from "./ActivityFeed.module.css";

const EVENT_COLORS: Record<string, string> = {
  ProductionStartedEvent: "var(--status-info)",
  ProductionCompletedEvent: "var(--status-ok)",
  TriggerFiredEvent: "var(--status-warn)",
  WorkOrderCreated: "var(--status-info)",
  WorkOrderAccepted: "var(--accent)",
  WorkOrderDelivered: "var(--status-warn)",
  WorkOrderCompleted: "var(--status-ok)",
  WorkOrderCancelled: "var(--status-error)",
  BpoListed: "var(--status-info)",
  BpoSold: "var(--status-ok)",
  BpcListed: "var(--status-info)",
  BpcSold: "var(--status-ok)",
  LeaseCreated: "var(--status-info)",
  LeaseReturned: "var(--status-ok)",
  LeaseForfeited: "var(--status-error)",
};

function stripEventSuffix(type: string): string {
  return type.replace(/Event$/, "");
}

export function ActivityFeed() {
  const { data: events = [], isLoading } = useEvents(50);

  if (isLoading) return <div className={styles.loading}>Loading events...</div>;
  if (events.length === 0) return <div className={styles.empty}>No events yet</div>;

  return (
    <div className={styles.feed}>
      {events.map((ev) => (
        <div key={ev.id} className={styles.entry}>
          <span
            className={styles.dot}
            style={{ background: EVENT_COLORS[ev.type] ?? "var(--text-muted)" }}
          />
          <span className={styles.time}>{formatTimestamp(ev.timestamp)}</span>
          <span className={styles.type}>{stripEventSuffix(ev.type)}</span>
        </div>
      ))}
    </div>
  );
}
