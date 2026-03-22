import { ConnectButton, useCurrentAccount } from "@mysten/dapp-kit";
import { PaneMenu } from "./PaneMenu";
import styles from "./TopBar.module.css";

interface Props {
  openPanes: Set<string>;
  onAddPane: (id: string) => void;
}

export function TopBar({ openPanes, onAddPane }: Props) {
  const account = useCurrentAccount();
  const network = import.meta.env.VITE_NETWORK ?? "testnet";

  return (
    <header className={styles.bar}>
      <div className={styles.logo}>INDUSTRIAL AUTO OS</div>
      <PaneMenu openPanes={openPanes} onAdd={onAddPane} />
      <div className={styles.right}>
        <span className={styles.network}>{network}</span>
        <ConnectButton />
      </div>
    </header>
  );
}
