import { useState } from "react";
import { useSignAndExecuteTransaction, useCurrentAccount } from "@mysten/dapp-kit";
import { useQueryClient } from "@tanstack/react-query";
import { useWorkOrders } from "../hooks/useWorkOrders";
import { truncateAddress, formatSui, formatTimestamp } from "../lib/format";
import { useToast } from "../hooks/useToast";
import { humanError } from "../lib/errors";
import { ORDER_STATUS, ORDER_STATUS_LABEL, ORDER_PRIORITY_LABEL } from "../lib/types";
import { PACKAGE_IDS, SHARED_OBJECTS } from "../lib/constants";
import { StatusBadge } from "../components/StatusBadge";
import {
  buildAcceptWorkOrder,
  buildDeliverWorkOrder,
  buildCompleteWorkOrder,
  buildAutoCompleteWorkOrder,
  buildCancelWorkOrder,
  buildCancelExpiredOrder,
} from "../lib/ptb/workOrder";
import styles from "./WorkOrderDetail.module.css";

const STATUS_VARIANT: Record<number, "ok" | "warn" | "error" | "info"> = {
  [ORDER_STATUS.OPEN]: "info",
  [ORDER_STATUS.ACCEPTED]: "warn",
  [ORDER_STATUS.DELIVERING]: "warn",
  [ORDER_STATUS.DELIVERED]: "ok",
  [ORDER_STATUS.COMPLETED]: "ok",
  [ORDER_STATUS.CANCELLED]: "error",
};

const SEVENTY_TWO_HOURS_MS = 72 * 60 * 60 * 1000;

export function WorkOrderDetail() {
  const account = useCurrentAccount();
  const queryClient = useQueryClient();
  const { data: orders } = useWorkOrders();
  const { mutate: signAndExecute } = useSignAndExecuteTransaction();
  const { addToast } = useToast();

  const [selectedId, setSelectedId] = useState("");
  const [deliverItemTypeId, setDeliverItemTypeId] = useState(0);
  const [deliverQuantity, setDeliverQuantity] = useState(1);

  const order = (orders ?? []).find((o) => o.id === selectedId);
  const now = Date.now();

  function runTx(tx: ReturnType<typeof buildAcceptWorkOrder>, action = "Transaction") {
    signAndExecute(
      { transaction: tx },
      {
        onSuccess: () => {
          queryClient.invalidateQueries({ queryKey: ["work-orders"] });
          addToast(`${action} succeeded`, "ok");
        },
        onError: (err: Error) => {
          const match = err.message.match(/MoveAbort.*?(\d+)\)$/);
          addToast(match ? humanError(Number(match[1])) : err.message, "error");
        },
      },
    );
  }

  const isIssuer = account && order && order.issuer === account.address;
  const isAcceptor = account && order && order.acceptor === account.address;
  const isExpired = order && order.deadline < now && order.status < ORDER_STATUS.COMPLETED;
  const canAutoComplete =
    order &&
    order.status === ORDER_STATUS.DELIVERED &&
    order.deliveredAt !== null &&
    now - order.deliveredAt >= SEVENTY_TWO_HOURS_MS;

  return (
    <div className={styles.container}>
      <div className={styles.selector}>
        <select
          className={styles.select}
          value={selectedId}
          onChange={(e) => setSelectedId(e.target.value)}
        >
          <option value="">-- Select Order --</option>
          {(orders ?? []).map((o) => (
            <option key={o.id} value={o.id}>
              {truncateAddress(o.id)} [{ORDER_STATUS_LABEL[o.status]}]
            </option>
          ))}
        </select>
      </div>

      {!order ? (
        <div className={styles.empty}>Select an order from the list</div>
      ) : (
        <>
          <div className={styles.detail}>
            <div className={styles.row}>
              <span className={styles.label}>ID</span>
              <span className={styles.value}>{order.id}</span>
            </div>
            <div className={styles.row}>
              <span className={styles.label}>Issuer</span>
              <span className={styles.value}>{truncateAddress(order.issuer)}</span>
            </div>
            <div className={styles.row}>
              <span className={styles.label}>Description</span>
              <span className={styles.value}>{order.description}</span>
            </div>
            <div className={styles.row}>
              <span className={styles.label}>Recipe</span>
              <span className={styles.value}>{truncateAddress(order.recipeId)}</span>
            </div>
            <div className={styles.row}>
              <span className={styles.label}>Quantity</span>
              <span className={styles.value}>
                {order.quantityDelivered}/{order.quantityRequired}
              </span>
            </div>
            <div className={styles.row}>
              <span className={styles.label}>Escrow</span>
              <span className={styles.value}>{formatSui(order.escrowValue)} SUI</span>
            </div>
            <div className={styles.row}>
              <span className={styles.label}>Deadline</span>
              <span className={styles.value}>{formatTimestamp(order.deadline)}</span>
            </div>
            <div className={styles.row}>
              <span className={styles.label}>Status</span>
              <span className={styles.value}>
                <StatusBadge
                  label={ORDER_STATUS_LABEL[order.status] ?? "Unknown"}
                  variant={STATUS_VARIANT[order.status] ?? "muted"}
                />
              </span>
            </div>
            <div className={styles.row}>
              <span className={styles.label}>Priority</span>
              <span className={styles.value}>
                {ORDER_PRIORITY_LABEL[order.priority] ?? "?"}
              </span>
            </div>
            {order.acceptor && (
              <div className={styles.row}>
                <span className={styles.label}>Acceptor</span>
                <span className={styles.value}>{truncateAddress(order.acceptor)}</span>
              </div>
            )}
            {order.sourceEvent && (
              <div className={styles.row}>
                <span className={styles.label}>Source Event</span>
                <span className={styles.value}>{order.sourceEvent}</span>
              </div>
            )}
            {order.deliveredAt !== null && (
              <div className={styles.row}>
                <span className={styles.label}>Delivered At</span>
                <span className={styles.value}>{formatTimestamp(order.deliveredAt)}</span>
              </div>
            )}
          </div>

          {/* Actions */}
          {account && order.status < ORDER_STATUS.COMPLETED && (
            <div className={styles.actions}>
              <div className={styles.actionsTitle}>Actions</div>

              {/* OPEN: Accept / Cancel */}
              {order.status === ORDER_STATUS.OPEN && (
                <div className={styles.actionRow}>
                  {!isIssuer && (
                    <button
                      className={styles.btn}
                      onClick={() =>
                        runTx(buildAcceptWorkOrder(PACKAGE_IDS.work_order, order.id), "Accept")
                      }
                    >
                      Accept
                    </button>
                  )}
                  {isIssuer && (
                    <button
                      className={`${styles.btn} ${styles.btnDanger}`}
                      onClick={() =>
                        runTx(
                          buildCancelWorkOrder(
                            PACKAGE_IDS.work_order,
                            order.id,
                            SHARED_OBJECTS.work_order_board,
                          ),
                          "Cancel",
                        )
                      }
                    >
                      Cancel
                    </button>
                  )}
                </div>
              )}

              {/* DELIVERING: Deliver form */}
              {order.status === ORDER_STATUS.DELIVERING && isAcceptor && (
                <div className={styles.actionRow}>
                  <input
                    className={styles.input}
                    type="number"
                    placeholder="Item Type"
                    value={deliverItemTypeId}
                    onChange={(e) => setDeliverItemTypeId(Number(e.target.value))}
                  />
                  <input
                    className={styles.input}
                    type="number"
                    placeholder="Qty"
                    min={1}
                    value={deliverQuantity}
                    onChange={(e) => setDeliverQuantity(Math.max(1, Number(e.target.value)))}
                  />
                  <button
                    className={styles.btn}
                    onClick={() =>
                      runTx(
                        buildDeliverWorkOrder(
                          PACKAGE_IDS.work_order,
                          order.id,
                          deliverItemTypeId,
                          deliverQuantity,
                        ),
                        "Deliver",
                      )
                    }
                  >
                    Deliver
                  </button>
                </div>
              )}

              {/* DELIVERED: Complete / Auto-complete */}
              {order.status === ORDER_STATUS.DELIVERED && (
                <div className={styles.actionRow}>
                  {isIssuer && (
                    <button
                      className={styles.btn}
                      onClick={() =>
                        runTx(
                          buildCompleteWorkOrder(
                            PACKAGE_IDS.work_order,
                            order.id,
                            SHARED_OBJECTS.work_order_board,
                          ),
                          "Complete",
                        )
                      }
                    >
                      Complete
                    </button>
                  )}
                  {isAcceptor && canAutoComplete && (
                    <button
                      className={styles.btn}
                      onClick={() =>
                        runTx(
                          buildAutoCompleteWorkOrder(
                            PACKAGE_IDS.work_order,
                            order.id,
                            SHARED_OBJECTS.work_order_board,
                          ),
                          "Auto-complete",
                        )
                      }
                    >
                      Auto-Complete
                    </button>
                  )}
                </div>
              )}

              {/* Expired: anyone can cancel */}
              {isExpired && (
                <div className={styles.actionRow}>
                  <button
                    className={`${styles.btn} ${styles.btnDanger}`}
                    onClick={() =>
                      runTx(
                        buildCancelExpiredOrder(
                          PACKAGE_IDS.work_order,
                          order.id,
                          SHARED_OBJECTS.work_order_board,
                        ),
                        "Cancel expired",
                      )
                    }
                  >
                    Cancel Expired
                  </button>
                </div>
              )}
            </div>
          )}
        </>
      )}
    </div>
  );
}
