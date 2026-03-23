import { useState } from "react";
import { useSuiClient, useSignAndExecuteTransaction, useCurrentAccount } from "@mysten/dapp-kit";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useToast } from "../hooks/useToast";
import { humanError } from "../lib/errors";
import { PACKAGE_IDS, SHARED_OBJECTS, TYPE_STRINGS } from "../lib/constants";
import { PASS_TYPE_LABEL } from "../lib/types";
import { truncateAddress, formatTimestamp } from "../lib/format";
import { StatusBadge } from "../components/StatusBadge";
import {
  buildClaimFromBlueprint,
  buildClaimFromLease,
  buildClaimFromWorkOrder,
  buildSurrenderPass,
  buildAdminRevokePass,
} from "../lib/ptb/factoryAccess";
import type { AccessPassData } from "../lib/types";
import styles from "./GateAccess.module.css";

export function GateAccess() {
  const account = useCurrentAccount();
  const client = useSuiClient();
  const queryClient = useQueryClient();
  const { mutate: signAndExecute } = useSignAndExecuteTransaction();
  const { addToast } = useToast();

  const [showClaim, setShowClaim] = useState(false);
  const [claimType, setClaimType] = useState<"blueprint" | "lease" | "work_order">("blueprint");
  const [sourceId, setSourceId] = useState("");
  const [lineId, setLineId] = useState("");

  const addr = account?.address ?? "";
  const pkg = PACKAGE_IDS.eve_integration;

  const { data: passes = [] } = useQuery({
    queryKey: ["access-passes", addr],
    queryFn: async (): Promise<AccessPassData[]> => {
      if (!account) return [];
      const { data } = await client.getOwnedObjects({
        owner: account.address,
        filter: {
          StructType: TYPE_STRINGS.AccessPass(PACKAGE_IDS.eve_integration),
        },
        options: { showContent: true },
      });
      return data.map((item) => {
        const f = (item.data!.content as any).fields;
        return {
          id: item.data!.objectId,
          factoryId: f.factory_id,
          holder: f.holder,
          passType: Number(f.pass_type),
          expiresAt: f.expires_at ?? null,
        };
      });
    },
    refetchInterval: 5000,
  });

  function onError(err: Error) {
    const match = err.message.match(/MoveAbort.*?(\d+)\)$/);
    addToast(match ? humanError(Number(match[1])) : err.message, "error");
  }

  function handleSurrender(passId: string) {
    const tx = buildSurrenderPass(pkg, SHARED_OBJECTS.access_registry, passId);
    signAndExecute({ transaction: tx }, {
      onSuccess: () => {
        queryClient.invalidateQueries({ queryKey: ["access-passes"] });
        addToast("Pass surrendered", "ok");
      },
      onError,
    });
  }

  function handleAdminRevoke(passId: string, factoryId: string) {
    const tx = buildAdminRevokePass(pkg, SHARED_OBJECTS.access_registry, passId, factoryId);
    signAndExecute({ transaction: tx }, {
      onSuccess: () => {
        queryClient.invalidateQueries({ queryKey: ["access-passes"] });
        addToast("Pass revoked (admin)", "ok");
      },
      onError,
    });
  }

  function handleClaim() {
    if (!sourceId || !lineId) return;
    let tx;
    switch (claimType) {
      case "blueprint":
        tx = buildClaimFromBlueprint(pkg, SHARED_OBJECTS.access_registry, sourceId, lineId);
        break;
      case "lease":
        tx = buildClaimFromLease(pkg, SHARED_OBJECTS.access_registry, sourceId, lineId);
        break;
      case "work_order":
        tx = buildClaimFromWorkOrder(pkg, SHARED_OBJECTS.access_registry, sourceId, lineId);
        break;
    }
    signAndExecute({ transaction: tx }, {
      onSuccess: () => {
        queryClient.invalidateQueries({ queryKey: ["access-passes"] });
        setSourceId("");
        setLineId("");
        addToast("Access pass claimed", "ok");
      },
      onError,
    });
  }

  const now = Date.now();

  return (
    <div className={styles.container}>
      {passes.length === 0 ? (
        <div className={styles.empty}>No access passes</div>
      ) : (
        <table className={styles.table}>
          <thead>
            <tr>
              <th>ID</th>
              <th>Factory</th>
              <th>Type</th>
              <th>Expires</th>
              <th>Status</th>
              <th>Actions</th>
            </tr>
          </thead>
          <tbody>
            {passes.map((p) => {
              const expired = p.expiresAt ? Number(p.expiresAt) < now : false;
              const isHolder = p.holder === addr;
              return (
                <tr key={p.id}>
                  <td>{truncateAddress(p.id)}</td>
                  <td>{truncateAddress(p.factoryId)}</td>
                  <td>{PASS_TYPE_LABEL[p.passType] ?? "Unknown"}</td>
                  <td>{p.expiresAt ? formatTimestamp(Number(p.expiresAt)) : "Never"}</td>
                  <td>
                    <StatusBadge
                      label={expired ? "Expired" : "Active"}
                      variant={expired ? "warn" : "ok"}
                    />
                  </td>
                  <td className={styles.actions}>
                    {isHolder && (
                      <button className={styles.btn} onClick={() => handleSurrender(p.id)} disabled={!account}>
                        Surrender
                      </button>
                    )}
                    <button
                      className={`${styles.btn} ${styles.btnDanger}`}
                      onClick={() => handleAdminRevoke(p.id, p.factoryId)}
                      disabled={!account}
                    >
                      Admin Revoke
                    </button>
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      )}

      <div className={styles.section}>
        <div className={styles.sectionTitle} onClick={() => setShowClaim(!showClaim)}>
          {showClaim ? "- Hide" : "+ Claim Access Pass"}
        </div>
        {showClaim && (
          <>
            <div className={styles.formRow}>
              <span className={styles.label}>Type</span>
              <select className={styles.select} value={claimType} onChange={(e) => setClaimType(e.target.value as any)} disabled={!account}>
                <option value="blueprint">Blueprint</option>
                <option value="lease">Lease</option>
                <option value="work_order">Work Order</option>
              </select>
            </div>
            <div className={styles.formRow}>
              <span className={styles.label}>Source ID</span>
              <input className={styles.input} placeholder="BPO / Lease / WO object ID" value={sourceId} onChange={(e) => setSourceId(e.target.value)} disabled={!account} />
            </div>
            <div className={styles.formRow}>
              <span className={styles.label}>Line ID</span>
              <input className={styles.input} placeholder="ProductionLine object ID" value={lineId} onChange={(e) => setLineId(e.target.value)} disabled={!account} />
            </div>
            <button className={styles.btn} onClick={handleClaim} disabled={!account || !sourceId || !lineId}>
              Claim Pass
            </button>
          </>
        )}
      </div>
    </div>
  );
}
