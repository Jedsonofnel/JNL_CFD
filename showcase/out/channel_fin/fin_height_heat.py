#!/usr/bin/env python3
"""
Fin height vs heat removed — single-series line plot.
Reads fin_height_heat.csv, outputs fin_height_heat.pdf/.png.
Non-converged points (negative or statistical outliers) are excluded.
"""
import csv
import numpy as np
import matplotlib.pyplot as plt
import matplotlib as mpl

# ── Palette (jnl.gp M.colour) ─────────────────────────────────
BLUE = "#0077bb"

# ── Shared rcParams ───────────────────────────────────────────
mpl.rcParams.update(
    {
        "font.family": "sans-serif",
        "font.sans-serif": ["Liberation Sans", "DejaVu Sans"],
        "font.size": 18,
        "mathtext.fontset": "dejavusans",
        "axes.linewidth": 1.4,
        "axes.titlesize": 26,
        "axes.labelsize": 22,
        "xtick.direction": "out",
        "ytick.direction": "out",
        "xtick.major.width": 1.2,
        "ytick.major.width": 1.2,
        "xtick.labelsize": 16,
        "ytick.labelsize": 16,
        "legend.fontsize": 19,
    }
)

# ── Load data ─────────────────────────────────────────────────
xs, ys = [], []
with open("fin_height_heat.csv", newline="") as f:
    reader = csv.DictReader(f)
    headers = reader.fieldnames or []
    xcol, ycol = headers[0], headers[1]
    for row in reader:
        try:
            xs.append(float(row[xcol]))
            ys.append(float(row[ycol]))
        except ValueError:
            pass

xs = np.array(xs)
ys = np.array(ys)

# ── Filter non-converged points ───────────────────────────────
# Pass 1: remove non-physical negatives
mask = ys > 0

# Pass 2: IQR outlier rejection on the remaining values
y_clean = ys[mask]
q1, q3 = np.percentile(y_clean, 25), np.percentile(y_clean, 75)
iqr = q3 - q1
upper_fence = q3 + 1.5 * iqr
mask &= ys <= upper_fence

n_excluded = len(ys) - mask.sum()
if n_excluded:
    print(f"Excluded {n_excluded} non-converged point(s):")
    for xi, yi in zip(xs[~mask], ys[~mask]):
        print(f"  h={xi:.4f}, Q={yi:.6f}")

xs, ys = xs[mask], ys[mask]

# ── Plot ──────────────────────────────────────────────────────
fig, ax = plt.subplots(figsize=(11.66, 7.28))  # 16:10, two-column A2
ax.plot(xs, ys, color=BLUE, lw=2.0, zorder=4)
ax.scatter(xs, ys, color=BLUE, s=70, zorder=5)
ax.set_xlabel(r"Fin Height  $h$  [m]")
ax.set_ylabel(r"Heat Removed  $Q$  [W]")
ax.set_title(r"$\bf{Fin\ Height\ vs\ Heat\ Removed}$")
ax.grid(True, color="#dddddd", linewidth=1.0, zorder=0)
ax.spines["top"].set_visible(False)
ax.spines["right"].set_visible(False)
plt.tight_layout()
plt.savefig("fin_height_heat.pdf", bbox_inches="tight")
plt.savefig("fin_height_heat.png", dpi=200, bbox_inches="tight")
plt.close(fig)
print("Saved fin_height_heat.pdf / .png")
