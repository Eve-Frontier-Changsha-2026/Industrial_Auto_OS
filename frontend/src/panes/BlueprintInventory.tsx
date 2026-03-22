import { useCurrentAccount } from "@mysten/dapp-kit";
import { useBlueprints } from "../hooks/useBlueprints";
import { truncateAddress } from "../lib/format";
import styles from "./BlueprintInventory.module.css";

function EffBar({ value }: { value: number }) {
  const pct = Math.min(Math.max(value, 0), 100);
  return (
    <span className={styles.effTrack}>
      <span className={styles.effBar} style={{ width: `${pct}%` }} />
    </span>
  );
}

export function BlueprintInventory() {
  const account = useCurrentAccount();
  const { bpos, bpcs } = useBlueprints();

  if (!account) {
    return <div className={styles.empty}>Connect wallet to view blueprints</div>;
  }

  return (
    <div className={styles.container}>
      {/* BPO Section */}
      <div className={styles.section}>
        <div className={styles.sectionTitle}>Originals (BPO)</div>
        {bpos.isLoading ? (
          <div className={styles.empty}>Loading...</div>
        ) : !bpos.data?.length ? (
          <div className={styles.empty}>No blueprint originals found</div>
        ) : (
          <table className={styles.table}>
            <thead>
              <tr>
                <th>ID</th>
                <th>Recipe</th>
                <th>ME%</th>
                <th>TE%</th>
                <th>Copies</th>
              </tr>
            </thead>
            <tbody>
              {bpos.data.map((bpo) => (
                <tr key={bpo.id}>
                  <td>{truncateAddress(bpo.id)}</td>
                  <td>{truncateAddress(bpo.recipeId)}</td>
                  <td>
                    <EffBar value={bpo.materialEfficiency} />
                    {bpo.materialEfficiency}%
                  </td>
                  <td>
                    <EffBar value={bpo.timeEfficiency} />
                    {bpo.timeEfficiency}%
                  </td>
                  <td>
                    {bpo.copiesMinted}/{bpo.maxCopies}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      {/* BPC Section */}
      <div className={styles.section}>
        <div className={styles.sectionTitle}>Copies (BPC)</div>
        {bpcs.isLoading ? (
          <div className={styles.empty}>Loading...</div>
        ) : !bpcs.data?.length ? (
          <div className={styles.empty}>No blueprint copies found</div>
        ) : (
          <table className={styles.table}>
            <thead>
              <tr>
                <th>ID</th>
                <th>Recipe</th>
                <th>Source BPO</th>
                <th>Uses</th>
                <th>ME%</th>
                <th>TE%</th>
              </tr>
            </thead>
            <tbody>
              {bpcs.data.map((bpc) => (
                <tr key={bpc.id}>
                  <td>{truncateAddress(bpc.id)}</td>
                  <td>{truncateAddress(bpc.recipeId)}</td>
                  <td>{truncateAddress(bpc.sourceBpoId)}</td>
                  <td>{bpc.usesRemaining}</td>
                  <td>
                    <EffBar value={bpc.materialEfficiency} />
                    {bpc.materialEfficiency}%
                  </td>
                  <td>
                    <EffBar value={bpc.timeEfficiency} />
                    {bpc.timeEfficiency}%
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  );
}
