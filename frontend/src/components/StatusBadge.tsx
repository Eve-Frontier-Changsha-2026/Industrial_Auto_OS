import styles from "./StatusBadge.module.css";

type Variant = "ok" | "warn" | "error" | "info" | "muted";

interface Props {
  label: string;
  variant?: Variant;
}

export function StatusBadge({ label, variant = "muted" }: Props) {
  return <span className={`${styles.badge} ${styles[variant]}`}>{label}</span>;
}
