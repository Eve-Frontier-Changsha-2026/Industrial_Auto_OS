import { useState } from "react";
import { useSignAndExecuteTransaction, useCurrentAccount } from "@mysten/dapp-kit";
import { useQueryClient } from "@tanstack/react-query";
import { useMarketplace } from "../hooks/useMarketplace";
import { useBlueprints } from "../hooks/useBlueprints";
import { formatSui, truncateAddress } from "../lib/format";
import { PACKAGE_IDS, SHARED_OBJECTS } from "../lib/constants";
import { useToast } from "../hooks/useToast";
import { humanError } from "../lib/errors";
import {
  buildListBpo, buildDelistBpo, buildBuyBpo,
  buildListBpc, buildDelistBpc, buildBuyBpc,
} from "../lib/ptb/marketplace";
import styles from "./MarketListings.module.css";

type Tab = "bpo" | "bpc";

export function MarketListings() {
  const [tab, setTab] = useState<Tab>("bpo");
  const account = useCurrentAccount();
  const queryClient = useQueryClient();
  const { mutate: signAndExecute } = useSignAndExecuteTransaction();
  const { addToast } = useToast();
  const { bpoListings, bpcListings } = useMarketplace();
  const { bpos, bpcs } = useBlueprints();

  // list form state
  const [listId, setListId] = useState("");
  const [listPrice, setListPrice] = useState("");

  const pkg = PACKAGE_IDS.marketplace;
  const mkt = SHARED_OBJECTS.marketplace;
  const addr = account?.address ?? "";

  function handleBuyBpo(listingId: string, price: number) {
    const tx = buildBuyBpo(pkg, mkt, listingId, BigInt(price));
    signAndExecute({ transaction: tx }, {
      onSuccess: () => {
        queryClient.invalidateQueries({ queryKey: ["market-bpo-listings"] });
        addToast("Purchase complete", "ok");
      },
      onError: (err: Error) => {
        const match = err.message.match(/MoveAbort.*?(\d+)\)$/);
        addToast(match ? humanError(Number(match[1])) : err.message, "error");
      },
    });
  }

  function handleDelistBpo(listingId: string) {
    const tx = buildDelistBpo(pkg, listingId, addr);
    signAndExecute({ transaction: tx }, {
      onSuccess: () => {
        queryClient.invalidateQueries({ queryKey: ["market-bpo-listings"] });
        addToast("Listing removed", "ok");
      },
      onError: (err: Error) => {
        const match = err.message.match(/MoveAbort.*?(\d+)\)$/);
        addToast(match ? humanError(Number(match[1])) : err.message, "error");
      },
    });
  }

  function handleListBpo() {
    if (!listId || !listPrice) return;
    const tx = buildListBpo(pkg, mkt, listId, Number(listPrice));
    signAndExecute({ transaction: tx }, {
      onSuccess: () => {
        queryClient.invalidateQueries({ queryKey: ["market-bpo-listings"] });
        setListId("");
        setListPrice("");
        addToast("Listed successfully", "ok");
      },
      onError: (err: Error) => {
        const match = err.message.match(/MoveAbort.*?(\d+)\)$/);
        addToast(match ? humanError(Number(match[1])) : err.message, "error");
      },
    });
  }

  function handleBuyBpc(listingId: string, price: number) {
    const tx = buildBuyBpc(pkg, mkt, listingId, BigInt(price));
    signAndExecute({ transaction: tx }, {
      onSuccess: () => {
        queryClient.invalidateQueries({ queryKey: ["market-bpc-listings"] });
        addToast("Purchase complete", "ok");
      },
      onError: (err: Error) => {
        const match = err.message.match(/MoveAbort.*?(\d+)\)$/);
        addToast(match ? humanError(Number(match[1])) : err.message, "error");
      },
    });
  }

  function handleDelistBpc(listingId: string) {
    const tx = buildDelistBpc(pkg, listingId, addr);
    signAndExecute({ transaction: tx }, {
      onSuccess: () => {
        queryClient.invalidateQueries({ queryKey: ["market-bpc-listings"] });
        addToast("Listing removed", "ok");
      },
      onError: (err: Error) => {
        const match = err.message.match(/MoveAbort.*?(\d+)\)$/);
        addToast(match ? humanError(Number(match[1])) : err.message, "error");
      },
    });
  }

  function handleListBpc() {
    if (!listId || !listPrice) return;
    const tx = buildListBpc(pkg, mkt, listId, Number(listPrice));
    signAndExecute({ transaction: tx }, {
      onSuccess: () => {
        queryClient.invalidateQueries({ queryKey: ["market-bpc-listings"] });
        setListId("");
        setListPrice("");
        addToast("Listed successfully", "ok");
      },
      onError: (err: Error) => {
        const match = err.message.match(/MoveAbort.*?(\d+)\)$/);
        addToast(match ? humanError(Number(match[1])) : err.message, "error");
      },
    });
  }

  const isBpo = tab === "bpo";
  const listings = isBpo ? bpoListings.data ?? [] : bpcListings.data ?? [];
  const ownItems = isBpo ? bpos.data ?? [] : bpcs.data ?? [];

  return (
    <div className={styles.container}>
      <div className={styles.tabs}>
        <button
          className={`${styles.tab} ${tab === "bpo" ? styles.tabActive : ""}`}
          onClick={() => { setTab("bpo"); setListId(""); setListPrice(""); }}
        >
          BPO Market
        </button>
        <button
          className={`${styles.tab} ${tab === "bpc" ? styles.tabActive : ""}`}
          onClick={() => { setTab("bpc"); setListId(""); setListPrice(""); }}
        >
          BPC Market
        </button>
      </div>

      <div className={styles.listings}>
        {listings.length === 0 && <div className={styles.empty}>No listings</div>}
        {listings.map((l) => {
          const isSeller = l.seller === addr;
          return (
            <div key={l.id} className={styles.card}>
              <div className={styles.cardInfo}>
                <span className={styles.price}>{formatSui(l.price)} SUI</span>
                <span className={styles.seller}>
                  {truncateAddress(l.seller)} &middot; {truncateAddress(l.id)}
                </span>
              </div>
              <div className={styles.cardActions}>
                {isSeller ? (
                  <button
                    className={`${styles.btn} ${styles.btnDanger}`}
                    onClick={() => isBpo ? handleDelistBpo(l.id) : handleDelistBpc(l.id)}
                    disabled={!account}
                  >
                    Delist
                  </button>
                ) : (
                  <button
                    className={styles.btn}
                    onClick={() => isBpo ? handleBuyBpo(l.id, l.price) : handleBuyBpc(l.id, l.price)}
                    disabled={!account}
                  >
                    Buy
                  </button>
                )}
              </div>
            </div>
          );
        })}
      </div>

      {/* List form */}
      <div className={styles.listForm}>
        <select
          className={styles.select}
          value={listId}
          onChange={(e) => setListId(e.target.value)}
          disabled={!account}
        >
          <option value="">Select {isBpo ? "BPO" : "BPC"}</option>
          {ownItems.map((item) => (
            <option key={item.id} value={item.id}>
              {truncateAddress(item.id)}
            </option>
          ))}
        </select>
        <input
          className={styles.input}
          type="number"
          placeholder="Price (MIST)"
          value={listPrice}
          onChange={(e) => setListPrice(e.target.value)}
          disabled={!account}
        />
        <button
          className={styles.btn}
          onClick={isBpo ? handleListBpo : handleListBpc}
          disabled={!account || !listId || !listPrice}
        >
          List
        </button>
      </div>
    </div>
  );
}
