import { useToast } from "../hooks/useToast";
import styles from "./Toast.module.css";

export function ToastContainer() {
  const { toasts, dismiss } = useToast();

  if (toasts.length === 0) return null;

  return (
    <div className={styles.container}>
      {toasts.map((t) => (
        <div key={t.id} className={`${styles.toast} ${styles[t.variant]}`}>
          <span className={styles.msg}>{t.message}</span>
          <button className={styles.close} onClick={() => dismiss(t.id)}>
            ×
          </button>
        </div>
      ))}
    </div>
  );
}
