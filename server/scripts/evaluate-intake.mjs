import { readFileSync } from "node:fs";

const file = process.argv[2];
if (!file) {
  console.error("Usage: npm run evaluate:intake -- /absolute/path/paired-intake-times.csv");
  process.exit(1);
}

// One row per matched intake task: the same type of item, measured with both workflows.
// Times include capture, correction, and submission. No example measurements are fabricated.
const lines = readFileSync(file, "utf8").trim().split(/\r?\n/);
if (lines.shift()?.trim() !== "task_id,baseline_seconds,assisted_seconds") throw new Error("Expected header: task_id,baseline_seconds,assisted_seconds");
const rows = lines.map((line, index) => {
  const cells = line.split(",");
  if (cells.length !== 3 || !cells[0].trim()) throw new Error(`Invalid row ${index + 2}`);
  const baseline = Number(cells[1]);
  const assisted = Number(cells[2]);
  if (!Number.isFinite(baseline) || baseline <= 0 || !Number.isFinite(assisted) || assisted < 0) throw new Error(`Invalid duration on row ${index + 2}`);
  return { taskId: cells[0].trim(), baseline, assisted };
});
if (rows.length < 10 || new Set(rows.map((row) => row.taskId)).size !== rows.length) throw new Error("At least 10 unique paired tasks are required");

const reduction = (sample) => 100 * (1 - sample.reduce((sum, row) => sum + row.assisted, 0) / sample.reduce((sum, row) => sum + row.baseline, 0));
let seed = 271828;
const random = () => { seed = (1664525 * seed + 1013904223) >>> 0; return seed / 2 ** 32; };
const draws = Array.from({ length: 10000 }, () => reduction(Array.from({ length: rows.length }, () => rows[Math.floor(random() * rows.length)]))).sort((a, b) => a - b);
const measured = reduction(rows);
const lower95 = draws[Math.floor(0.025 * draws.length)];
const upper95 = draws[Math.floor(0.975 * draws.length)];
console.log(JSON.stringify({ metric: "paired aggregate intake-time reduction", tasks: rows.length, baselineSeconds: rows.reduce((sum, row) => sum + row.baseline, 0), assistedSeconds: rows.reduce((sum, row) => sum + row.assisted, 0), reductionPercent: Number(measured.toFixed(2)), bootstrap95PercentInterval: [Number(lower95.toFixed(2)), Number(upper95.toFixed(2))], targetPercent: 40, targetMet: lower95 >= 40, note: "Use representative items and identical start/stop rules; this is not a randomized causal study." }, null, 2));
