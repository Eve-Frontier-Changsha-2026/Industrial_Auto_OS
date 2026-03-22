import { type ReactNode } from "react";
import styles from "./PaneChrome.module.css";

interface Props {
  title: string;
  minimized?: boolean;
  onMinimize?: () => void;
  onMaximize?: () => void;
  onClose?: () => void;
  children: ReactNode;
}

export function PaneChrome({ title, minimized, onMinimize, onMaximize, onClose, children }: Props) {
  return (
    <div className={`${styles.panel} ${minimized ? styles.minimized : ""}`}>
      <div className={styles.header} data-drag-handle>
        <span className={styles.title}>{title}</span>
        <div className={styles.controls}>
          {onMinimize && (
            <button className={styles.controlBtn} onClick={onMinimize} title="Minimize">_</button>
          )}
          {onMaximize && (
            <button className={styles.controlBtn} onClick={onMaximize} title="Maximize">[]</button>
          )}
          {onClose && (
            <button className={styles.controlBtn} onClick={onClose} title="Close">x</button>
          )}
        </div>
      </div>
      <div className={styles.body}>{children}</div>
    </div>
  );
}
