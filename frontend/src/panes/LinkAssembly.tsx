import { StatusBadge } from "../components/StatusBadge";
import styles from "./LinkAssembly.module.css";

export function LinkAssembly() {
  return (
    <div className={styles.container}>
      <div className={styles.section}>
        <div className={styles.sectionTitle}>Extension Status</div>
        <div className={styles.info}>
          <StatusBadge label="Not Linked" variant="muted" />{" "}
          Extension registration requires EVE Smart Assembly ownership.
          Once linked, your production lines can interact with SSU inventory and access gates.
        </div>
      </div>

      <div className={styles.section}>
        <div className={styles.sectionTitle}>Link Smart Assembly</div>
        <div className={styles.muted}>
          Linking connects your on-chain factory to an EVE Smart Assembly, enabling item flow between worlds.
        </div>
        <div className={styles.actions}>
          <button className={styles.btn} disabled>
            Link SSU
          </button>
          <button className={styles.btn} disabled>
            Link Gate
          </button>
        </div>
        <div className={styles.note}>
          These actions are disabled pending EVE world contract types.
          SSU and Smart Gate integration will become available once the EVE Frontier SDK publishes assembly type definitions.
        </div>
      </div>

      <div className={styles.section}>
        <div className={styles.sectionTitle}>Production Freeze</div>
        <div className={styles.info}>
          For production deployments, call <code>freeze_extension_config</code> after linking
          to prevent further configuration changes. This is a one-way operation.
        </div>
      </div>
    </div>
  );
}
