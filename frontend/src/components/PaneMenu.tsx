import { useState, useRef, useEffect } from "react";
import { PANE_DEFS } from "../config/paneRegistry";
import styles from "./PaneMenu.module.css";

interface Props {
  openPanes: Set<string>;
  onAdd: (id: string) => void;
}

export function PaneMenu({ openPanes, onAdd }: Props) {
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const handler = (e: MouseEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false);
    };
    document.addEventListener("mousedown", handler);
    return () => document.removeEventListener("mousedown", handler);
  }, []);

  const categories = [...new Set(PANE_DEFS.map((d) => d.category))];

  return (
    <div className={styles.wrapper} ref={ref}>
      <button className={styles.trigger} onClick={() => setOpen(!open)}>+ ADD PANEL</button>
      {open && (
        <div className={styles.dropdown}>
          {categories.map((cat) => (
            <div key={cat}>
              <div className={styles.catLabel}>{cat}</div>
              {PANE_DEFS.filter((d) => d.category === cat).map((d) => (
                <button
                  key={d.id}
                  className={styles.item}
                  disabled={openPanes.has(d.id)}
                  onClick={() => { onAdd(d.id); setOpen(false); }}
                >
                  {d.title} {openPanes.has(d.id) && "\u2713"}
                </button>
              ))}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
