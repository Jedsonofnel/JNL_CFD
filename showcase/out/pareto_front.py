#!/usr/bin/env python3
"""
Pareto front scatter plot — poster quality.
A2 four-column layout, main body font ~26pt.
Consistent with jnl/gp/init.lua defaults:
  - Font:        Arial (sans-serif), base 18pt
  - Aspect:      16:10 doubled → two-column width on A2
  - Colours:     jnl.gp palette (blue=dominated, red=front)
  - Grid:        on by default
  - Title:       bold
"""

import csv
import matplotlib.pyplot as plt
import matplotlib as mpl

# ── Palette (jnl.gp M.colour) ─────────────────────────────────
BLUE = "#0077bb"
RED = "#ee3333"

# ── Load data ─────────────────────────────────────────────────
dominated, front = [], []

with open("fin_pareto_coarse.csv", newline="") as f:
    for row in csv.DictReader(f):
        if row["ok"] != "1":
            continue
        dp = float(row["delta_p"])
        q = float(row["heat_removed"])
        if q <= 0:  # discard solver artefacts
            continue
        if int(row["front"]) == 1:
            front.append((dp, q))
        else:
            dominated.append((dp, q))

# Sort front by delta_p so the connecting line is monotone
front.sort(key=lambda t: t[0])

# ── Figure ────────────────────────────────────────────────────
# Size: DEFAULT_VECTOR_SIZE {16,10} cm doubled → 32×20 cm ≈ 11.66×7.28 in (16:10)
# Font: matches DEFAULT_FONT "Arial,18"; base size set globally so all
#       text (title, labels, ticks, legend) inherits and scales from it.
mpl.rcParams.update(
    {
        # Font — Arial with metric-compatible fallbacks
        "font.family": "sans-serif",
        "font.sans-serif": ["Arial", "Liberation Sans", "DejaVu Sans"],
        "font.size": 18,  # matches DEFAULT_FONT "Arial,18"
        "mathtext.fontset": "dejavusans",  # sans-serif math (Δ, Q, etc.)
        # Axes
        "axes.linewidth": 1.4,
        "axes.titlesize": 26,  # poster body ~26pt → title slightly larger
        "axes.labelsize": 22,
        # Ticks
        "xtick.direction": "out",
        "ytick.direction": "out",
        "xtick.major.width": 1.2,
        "ytick.major.width": 1.2,
        "xtick.labelsize": 16,
        "ytick.labelsize": 16,
        # Legend
        "legend.fontsize": 19,
    }
)

fig, ax = plt.subplots(figsize=(11.66, 7.28))  # 16:10, two-column width on A2

# Dominated cloud
if dominated:
    dx, dy = zip(*dominated)
    ax.scatter(dx, dy, color=BLUE, s=55, zorder=3, label="Dominated")

# Pareto front — dashed line then markers on top
if front:
    fx, fy = zip(*front)
    ax.plot(fx, fy, color=RED, lw=2.0, ls="--", zorder=4)
    ax.scatter(fx, fy, color=RED, s=90, marker="^", zorder=5, label="Pareto front")

# ── Labels & decorations ──────────────────────────────────────
ax.set_xlabel(r"Pressure Drop  $\Delta p$  [Pa]")
ax.set_ylabel(r"Heat Removed  $Q$  [W]")
ax.set_title(r"$\bf{Fin\ Array\ —\ Pareto\ Front}$")

ax.legend(
    loc="lower right",
    framealpha=0.9,
    edgecolor="#cccccc",
    handletextpad=0.6,
    borderpad=0.7,
)

ax.grid(True, color="#dddddd", linewidth=1.0, zorder=0)
ax.spines["top"].set_visible(False)
ax.spines["right"].set_visible(False)

plt.tight_layout()
plt.savefig("pareto_front.pdf", bbox_inches="tight")
plt.savefig("pareto_front.png", dpi=200, bbox_inches="tight")
print("Saved pareto_front.pdf / .png")
