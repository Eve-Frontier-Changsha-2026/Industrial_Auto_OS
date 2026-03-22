import { useState } from "react";
import { useSignAndExecuteTransaction, useCurrentAccount } from "@mysten/dapp-kit";
import { useQueryClient } from "@tanstack/react-query";
import { useBlueprints } from "../hooks/useBlueprints";
import { useToast } from "../hooks/useToast";
import { humanError } from "../lib/errors";
import { truncateAddress } from "../lib/format";
import { PACKAGE_IDS } from "../lib/constants";
import { buildMintBpc } from "../lib/ptb/blueprint";
import styles from "./BlueprintMint.module.css";

export function BlueprintMint() {
  const account = useCurrentAccount();
  const queryClient = useQueryClient();
  const { bpos } = useBlueprints();
  const { mutate: signAndExecute } = useSignAndExecuteTransaction();
  const { addToast } = useToast();

  const [selectedBpoId, setSelectedBpoId] = useState("");
  const [uses, setUses] = useState(1);

  if (!account) {
    return <div className={styles.empty}>Connect wallet to mint blueprints</div>;
  }

  const bpoList = bpos.data ?? [];
  const selectedBpo = bpoList.find((b) => b.id === selectedBpoId);
  const maxedOut = selectedBpo ? selectedBpo.copiesMinted >= selectedBpo.maxCopies : false;

  function handleMint() {
    if (!selectedBpo || !account) return;
    const tx = buildMintBpc(
      PACKAGE_IDS.industrial_core,
      selectedBpo.id,
      uses,
      account.address,
    );
    signAndExecute(
      { transaction: tx },
      {
        onSuccess: () => {
          queryClient.invalidateQueries({ queryKey: ["bpos"] });
          queryClient.invalidateQueries({ queryKey: ["bpcs"] });
          addToast("BPC minted successfully", "ok");
        },
        onError: (err: Error) => {
          const match = err.message.match(/MoveAbort.*?(\d+)\)$/);
          addToast(match ? humanError(Number(match[1])) : err.message, "error");
        },
      },
    );
  }

  return (
    <div className={styles.container}>
      <div className={styles.field}>
        <label className={styles.label}>Select BPO</label>
        <select
          className={styles.select}
          value={selectedBpoId}
          onChange={(e) => setSelectedBpoId(e.target.value)}
        >
          <option value="">-- Select --</option>
          {bpoList.map((bpo) => (
            <option key={bpo.id} value={bpo.id}>
              {truncateAddress(bpo.id)} (ME:{bpo.materialEfficiency}% TE:{bpo.timeEfficiency}%)
            </option>
          ))}
        </select>
      </div>

      {selectedBpo && (
        <div className={styles.info}>
          <div><span>Recipe: </span>{truncateAddress(selectedBpo.recipeId)}</div>
          <div><span>ME: </span>{selectedBpo.materialEfficiency}%</div>
          <div><span>TE: </span>{selectedBpo.timeEfficiency}%</div>
          <div>
            <span>Copies: </span>
            {selectedBpo.copiesMinted}/{selectedBpo.maxCopies}
            {maxedOut && " (maxed)"}
          </div>
        </div>
      )}

      <div className={styles.field}>
        <label className={styles.label}>Uses per copy</label>
        <input
          className={styles.input}
          type="number"
          min={1}
          value={uses}
          onChange={(e) => setUses(Math.max(1, Number(e.target.value)))}
        />
      </div>

      <button
        className={styles.btn}
        disabled={!selectedBpo || maxedOut}
        onClick={handleMint}
      >
        Mint BPC
      </button>
    </div>
  );
}
