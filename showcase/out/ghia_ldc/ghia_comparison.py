#!/usr/bin/env python3
"""
Ghia lid-driven cavity single-Re comparison plots.

Reads:
  ghia_u_comparison_Re7500UDS.csv
  ghia_v_comparison_Re7500UDS.csv

Writes:
  ghia_u_comparison_Re7500UDS.pdf/.png
  ghia_v_comparison_Re7500UDS.pdf/.png

CSV format expected:
  x_JNLCFD,y_JNLCFD,x_Ghia et al.,y_Ghia et al.

For u-comparison:
  x = u / U_lid, y = y / H

For v-comparison:
  x = x / L, y = v / U_lid
"""

import csv
import os
import re
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


# ── Helpers ───────────────────────────────────────────────────
def try_float(value):
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def parse_meta_from_filename(path):
    """
    Parse component, Re, and scheme from filenames like:
      ghia_u_comparison_Re7500UDS.csv
      ghia_v_comparison_Re7500UDS.csv
    """
    name = os.path.basename(path)
    match = re.match(r"ghia_([uv])_comparison_Re(\d+)([A-Za-z]+)\.csv$", name)

    if not match:
        return None, None, None

    component = match.group(1)
    reynolds = int(match.group(2))
    scheme = match.group(3).upper()

    return component, reynolds, scheme


def read_xy_comparison_csv(path):
    """
    Read comparison CSVs emitted by the JNL figure writer.

    The CSV columns are already plot-space x/y pairs:
      x_JNLCFD, y_JNLCFD, x_Ghia et al., y_Ghia et al.
    """
    x_jnl, y_jnl = [], []
    x_ghia, y_ghia = [], []

    with open(path, newline="") as f:
        reader = csv.DictReader(f)

        for row in reader:
            x = try_float(row.get("x_JNLCFD", ""))
            y = try_float(row.get("y_JNLCFD", ""))
            if x is not None and y is not None:
                x_jnl.append(x)
                y_jnl.append(y)

            xg = try_float(row.get("x_Ghia et al.", ""))
            yg = try_float(row.get("y_Ghia et al.", ""))
            if xg is not None and yg is not None:
                x_ghia.append(xg)
                y_ghia.append(yg)

    return x_jnl, y_jnl, x_ghia, y_ghia


# ── Plotting ──────────────────────────────────────────────────
def plot_comparison(path):
    component, reynolds, scheme = parse_meta_from_filename(path)

    if component not in ("u", "v"):
        print(f"Skipping {path} (unrecognised filename pattern)")
        return

    x_jnl, y_jnl, x_ghia, y_ghia = read_xy_comparison_csv(path)

    fig, ax = plt.subplots(figsize=(11.66, 7.28))  # 16:10, two-column A2

    ax.plot(
        x_jnl,
        y_jnl,
        color=BLUE,
        lw=2.0,
        zorder=4,
        label="JNLCFD",
    )

    ax.scatter(
        x_ghia,
        y_ghia,
        color=BLUE,
        s=90,
        marker="^",
        zorder=5,
        label="Ghia et al.",
    )

    if component == "u":
        ax.set_xlabel(r"$u \,/\, U_\mathrm{lid}$")
        ax.set_ylabel(r"$y \,/\, H$")
        ax.set_title(
            rf"$\bf{{Lid\text{{-}}Driven\ Cavity\ -\ u\ Velocity\ Profile}}$"
            + "\n"
            + rf"$Re = {reynolds}$, {scheme}"
        )
        legend_loc = "lower right"
    else:
        ax.set_xlabel(r"$x \,/\, L$")
        ax.set_ylabel(r"$v \,/\, U_\mathrm{lid}$")
        ax.set_title(
            rf"$\bf{{Lid\text{{-}}Driven\ Cavity\ -\ v\ Velocity\ Profile}}$"
            + "\n"
            + rf"$Re = {reynolds}$, {scheme}"
        )
        legend_loc = "lower left"

    ax.legend(
        loc=legend_loc,
        framealpha=0.9,
        edgecolor="#cccccc",
        handletextpad=0.6,
        borderpad=0.7,
        labelspacing=0.4,
    )

    ax.grid(True, color="#dddddd", linewidth=1.0, zorder=0)
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)

    out_stem = os.path.splitext(path)[0]

    plt.tight_layout()
    plt.savefig(out_stem + ".pdf", bbox_inches="tight")
    plt.savefig(out_stem + ".png", dpi=200, bbox_inches="tight")
    plt.close(fig)

    print(f"Saved {out_stem}.pdf / .png")


# ── Main ──────────────────────────────────────────────────────
FILES = [
    "ghia_u_comparison_Re7500UDS.csv",
    "ghia_v_comparison_Re7500UDS.csv",
]

for path in FILES:
    if os.path.exists(path):
        plot_comparison(path)
    else:
        print(f"Skipping {path} (not found)")
