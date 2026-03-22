import { useRecipes } from "../hooks/useRecipes";
import { formatDuration } from "../lib/format";
import styles from "./RecipeBrowser.module.css";

export function RecipeBrowser() {
  const { data: recipes = [] } = useRecipes();

  if (recipes.length === 0) {
    return <div className={styles.empty}>No recipes configured</div>;
  }

  return (
    <table className={styles.table}>
      <thead>
        <tr>
          <th>Name</th>
          <th>Inputs</th>
          <th>Output</th>
          <th>Duration</th>
          <th>Energy</th>
        </tr>
      </thead>
      <tbody>
        {recipes.map((r) => (
          <tr key={r.id}>
            <td className={styles.name}>{r.name}</td>
            <td>
              {r.inputs.map((i) => `#${i.itemTypeId} x${i.quantity}`).join(", ")}
            </td>
            <td>
              #{r.output.itemTypeId} x{r.output.quantity}
            </td>
            <td>{formatDuration(r.baseDurationMs)}</td>
            <td>{r.energyCost}</td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}
