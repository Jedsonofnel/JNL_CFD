#!/usr/bin/env python3
"""
Poiseuille flow validation — analytical vs numerical velocity profile.

Reads:
  poiseuille_comparison.csv

Expected columns:
  x_Numerical,y_Numerical,x_Analytical,y_Analytical

Writes:
  poiseuille_comparison.pdf
  poiseuille_comparison.png
"""

import csv
import os
import matplotlib.pyplot as plt
import matplotlib as mpl

BLUE = "#0077bb"
RED = "#ee3333"

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


def try_float(value):
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def read_comparison(path):
    x_num, y_num = [], []
    x_ana, y_ana = [], []

    with open(path, newline="") as f:
        reader = csv.DictReader(f)

        for row in reader:
            xn = try_float(row.get("x_Numerical", ""))
            yn = try_float(row.get("y_Numerical", ""))
            if xn is not None and yn is not None:
                x_num.append(xn)
                y_num.append(yn)

            xa = try_float(row.get("x_Analytical", ""))
            ya = try_float(row.get("y_Analytical", ""))
            if xa is not None and ya is not None:
                x_ana.append(xa)
                y_ana.append(ya)

    return x_num, y_num, x_ana, y_ana


def plot_comparison(path="poiseuille_comparison.csv"):
    if not os.path.exists(path):
        print(f"Skipping {path} (not found)")
        return

    x_num, y_num, x_ana, y_ana = read_comparison(path)

    fig, ax = plt.subplots(figsize=(11.66, 7.28))

    ax.plot(
        x_ana,
        y_ana,
        color=RED,
        lw=2.0,
        zorder=4,
        label="Analytical",
    )

    ax.scatter(
        x_num,
        y_num,
        color=BLUE,
        s=70,
        zorder=5,
        label="JNLCFD",
    )

    ax.set_xlabel(r"$u \,/\, U_\mathrm{mean}$")
    ax.set_ylabel(r"$y \,/\, H$")
    ax.set_title(r"$\bf{Poiseuille\ Flow\ Validation}$")

    ax.legend(
        loc="upper right",
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


plot_comparison()
