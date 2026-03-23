import { useState } from "react";
import { useSignAndExecuteTransaction, useCurrentAccount } from "@mysten/dapp-kit";
import { useQueryClient } from "@tanstack/react-query";
import { useToast } from "../hooks/useToast";
import { humanError } from "../lib/errors";
import { PACKAGE_IDS, SHARED_OBJECTS } from "../lib/constants";
import {
  buildAddGlobalMapping,
  buildRemoveGlobalMapping,
  buildDisableFactoryMapping,
  buildEnableFactoryMapping,
} from "../lib/ptb/eveBridge";
import styles from "./ItemMapping.module.css";

export function ItemMapping() {
  const account = useCurrentAccount();
  const queryClient = useQueryClient();
  const { mutate: signAndExecute } = useSignAndExecuteTransaction();
  const { addToast } = useToast();

  // Lookup
  const [lookupTypeId, setLookupTypeId] = useState("");

  // Admin add/remove
  const [adminCapId, setAdminCapId] = useState("");
  const [addTypeId, setAddTypeId] = useState("");
  const [addMaterialId, setAddMaterialId] = useState("");
  const [removeTypeId, setRemoveTypeId] = useState("");

  // Factory override
  const [overrideLineId, setOverrideLineId] = useState("");
  const [overrideTypeId, setOverrideTypeId] = useState("");

  const pkg = PACKAGE_IDS.eve_integration;

  function onError(err: Error) {
    const match = err.message.match(/MoveAbort.*?(\d+)\)$/);
    addToast(match ? humanError(Number(match[1])) : err.message, "error");
  }

  function handleAdd() {
    if (!adminCapId || !addTypeId || !addMaterialId) return;
    const tx = buildAddGlobalMapping(pkg, SHARED_OBJECTS.global_registry, adminCapId, addTypeId, addMaterialId);
    signAndExecute({ transaction: tx }, {
      onSuccess: () => {
        queryClient.invalidateQueries({ queryKey: ["item-mappings"] });
        setAddTypeId("");
        setAddMaterialId("");
        addToast("Mapping added", "ok");
      },
      onError,
    });
  }

  function handleRemove() {
    if (!adminCapId || !removeTypeId) return;
    const tx = buildRemoveGlobalMapping(pkg, SHARED_OBJECTS.global_registry, adminCapId, removeTypeId);
    signAndExecute({ transaction: tx }, {
      onSuccess: () => {
        queryClient.invalidateQueries({ queryKey: ["item-mappings"] });
        setRemoveTypeId("");
        addToast("Mapping removed", "ok");
      },
      onError,
    });
  }

  function handleDisable() {
    if (!overrideLineId || !overrideTypeId) return;
    const tx = buildDisableFactoryMapping(pkg, SHARED_OBJECTS.global_registry, overrideLineId, overrideTypeId);
    signAndExecute({ transaction: tx }, {
      onSuccess: () => {
        addToast("Mapping disabled for factory", "ok");
      },
      onError,
    });
  }

  function handleEnable() {
    if (!overrideLineId || !overrideTypeId) return;
    const tx = buildEnableFactoryMapping(pkg, SHARED_OBJECTS.global_registry, overrideLineId, overrideTypeId);
    signAndExecute({ transaction: tx }, {
      onSuccess: () => {
        addToast("Mapping enabled for factory", "ok");
      },
      onError,
    });
  }

  return (
    <div className={styles.container}>
      {/* Lookup */}
      <div className={styles.section}>
        <div className={styles.sectionTitle}>Lookup Mapping</div>
        <div className={styles.muted}>
          GlobalRegistry uses dynamic fields. Enter an EVE type ID to check mapping status.
        </div>
        <div className={styles.formRow}>
          <span className={styles.label}>EVE Type ID</span>
          <input className={styles.input} placeholder="e.g. 34" value={lookupTypeId} onChange={(e) => setLookupTypeId(e.target.value)} />
        </div>
        {lookupTypeId && (
          <div className={styles.result}>
            Lookup for type {lookupTypeId} requires on-chain devInspect (not yet connected).
          </div>
        )}
      </div>

      {/* Admin: Add / Remove */}
      <div className={styles.section}>
        <div className={styles.sectionTitle}>Admin: Manage Global Mappings</div>
        <div className={styles.formRow}>
          <span className={styles.label}>AdminCap ID</span>
          <input className={styles.input} placeholder="RegistryAdminCap object ID" value={adminCapId} onChange={(e) => setAdminCapId(e.target.value)} disabled={!account} />
        </div>

        <div className={styles.sectionTitle} style={{ marginTop: 8 }}>Add Mapping</div>
        <div className={styles.formRow}>
          <span className={styles.label}>EVE Type ID</span>
          <input className={styles.input} placeholder="e.g. 34" value={addTypeId} onChange={(e) => setAddTypeId(e.target.value)} disabled={!account} />
        </div>
        <div className={styles.formRow}>
          <span className={styles.label}>Material ID</span>
          <input className={styles.input} placeholder="material object ID" value={addMaterialId} onChange={(e) => setAddMaterialId(e.target.value)} disabled={!account} />
        </div>
        <button className={styles.btn} onClick={handleAdd} disabled={!account || !adminCapId || !addTypeId || !addMaterialId}>
          Add Mapping
        </button>

        <div className={styles.sectionTitle} style={{ marginTop: 8 }}>Remove Mapping</div>
        <div className={styles.formRow}>
          <span className={styles.label}>EVE Type ID</span>
          <input className={styles.input} placeholder="e.g. 34" value={removeTypeId} onChange={(e) => setRemoveTypeId(e.target.value)} disabled={!account} />
        </div>
        <button className={`${styles.btn} ${styles.btnDanger}`} onClick={handleRemove} disabled={!account || !adminCapId || !removeTypeId}>
          Remove Mapping
        </button>
      </div>

      {/* Factory Override */}
      <div className={styles.section}>
        <div className={styles.sectionTitle}>Factory Override</div>
        <div className={styles.muted}>
          Disable or re-enable a specific EVE type mapping for a production line you own.
        </div>
        <div className={styles.formRow}>
          <span className={styles.label}>Line ID</span>
          <input className={styles.input} placeholder="ProductionLine object ID" value={overrideLineId} onChange={(e) => setOverrideLineId(e.target.value)} disabled={!account} />
        </div>
        <div className={styles.formRow}>
          <span className={styles.label}>EVE Type ID</span>
          <input className={styles.input} placeholder="e.g. 34" value={overrideTypeId} onChange={(e) => setOverrideTypeId(e.target.value)} disabled={!account} />
        </div>
        <div className={styles.formRow}>
          <button className={`${styles.btn} ${styles.btnDanger}`} onClick={handleDisable} disabled={!account || !overrideLineId || !overrideTypeId}>
            Disable
          </button>
          <button className={styles.btn} onClick={handleEnable} disabled={!account || !overrideLineId || !overrideTypeId}>
            Enable
          </button>
        </div>
      </div>
    </div>
  );
}
