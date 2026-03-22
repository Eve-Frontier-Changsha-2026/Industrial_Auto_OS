import { Responsive, verticalCompactor, type Layout } from "react-grid-layout";
import "react-grid-layout/css/styles.css";
import "react-resizable/css/styles.css";
import { TopBar } from "./components/TopBar";
import { PaneChrome } from "./components/PaneChrome";
import { ToastContainer } from "./components/Toast";
import { ToastContext, useToastState } from "./hooks/useToast";
import { PANE_MAP } from "./config/paneRegistry";
import { useLayout } from "./hooks/useLayout";
import { usePaneManager } from "./hooks/usePaneManager";
import styles from "./App.module.css";

export default function App() {
  const { layout, onLayoutChange } = useLayout();
  const { openPanes, minimized, maximized, open, close, minimize, maximize } = usePaneManager();
  const toastState = useToastState();

  const visibleLayout = layout.filter((l) => openPanes.has(l.i));

  return (
    <ToastContext.Provider value={toastState}>
    <div className={styles.app}>
      <TopBar openPanes={openPanes} onAddPane={open} />
      <div className={styles.grid}>
        <Responsive
          className={styles.gridInner}
          layouts={{ lg: visibleLayout }}
          breakpoints={{ xl: 1600, lg: 1200, md: 996 }}
          cols={{ xl: 24, lg: 24, md: 24 }}
          rowHeight={30}
          margin={[4, 4] as [number, number]}
          dragConfig={{ handle: "[data-drag-handle]" }}
          compactor={verticalCompactor}
          onLayoutChange={(newLayout: Layout) => onLayoutChange(newLayout)}
          width={1200}
        >
          {[...openPanes].map((paneId) => {
            const def = PANE_MAP.get(paneId);
            if (!def) return null;
            const Comp = def.component;
            const isMinimized = minimized.has(paneId);

            if (maximized === paneId) return null;

            return (
              <div key={paneId}>
                <PaneChrome
                  title={def.title}
                  minimized={isMinimized}
                  onMinimize={() => minimize(paneId)}
                  onMaximize={() => maximize(paneId)}
                  onClose={() => close(paneId)}
                >
                  <Comp />
                </PaneChrome>
              </div>
            );
          })}
        </Responsive>

        {maximized && PANE_MAP.has(maximized) && (() => {
          const def = PANE_MAP.get(maximized)!;
          const Comp = def.component;
          return (
            <div className={styles.overlay}>
              <PaneChrome
                title={def.title}
                onMaximize={() => maximize(maximized)}
                onClose={() => close(maximized)}
              >
                <Comp />
              </PaneChrome>
            </div>
          );
        })()}
      </div>
      <ToastContainer />
    </div>
    </ToastContext.Provider>
  );
}
