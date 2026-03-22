import { useWatcherStatus, useWatcherHealth } from "../hooks/useWatcher";
import { formatTimestamp, formatDuration } from "../lib/format";
import { StatusBadge } from "../components/StatusBadge";
import styles from "./WatcherStatus.module.css";

export function WatcherStatus() {
  const { data: status, isError: statusError } = useWatcherStatus();
  const { data: health, isError: healthError } = useWatcherHealth();

  const offline = statusError || healthError;

  if (offline) {
    return (
      <div className={styles.container}>
        <div className={styles.offline}>Watcher Offline</div>
      </div>
    );
  }

  return (
    <div className={styles.container}>
      <div className={styles.health}>
        <div className={styles.healthItem}>
          <span className={styles.healthLabel}>Status</span>
          <span className={styles.healthValue}>
            <StatusBadge label={health?.status ?? "unknown"} variant={health?.status === "ok" ? "ok" : "error"} />
          </span>
        </div>
        <div className={styles.healthItem}>
          <span className={styles.healthLabel}>Uptime</span>
          <span className={styles.healthValue}>
            {health?.uptime_ms ? formatDuration(health.uptime_ms) : "--"}
          </span>
        </div>
        <div className={styles.healthItem}>
          <span className={styles.healthLabel}>Last Poll</span>
          <span className={styles.healthValue}>
            {health?.last_poll ? formatTimestamp(health.last_poll) : "--"}
          </span>
        </div>
      </div>

      <div className={styles.rules}>
        {(status?.rules ?? []).map((rule) => (
          <div key={rule.name} className={styles.rule}>
            <div className={styles.ruleInfo}>
              <span className={styles.ruleName}>{rule.name}</span>
              <span className={styles.ruleDesc}>{rule.description}</span>
            </div>
            <StatusBadge
              label={rule.enabled ? "Enabled" : "Disabled"}
              variant={rule.enabled ? "ok" : "muted"}
            />
          </div>
        ))}
      </div>
    </div>
  );
}
