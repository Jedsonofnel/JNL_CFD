#!/usr/bin/env python3
"""
Ghia et al. lid-driven cavity validation — u and v profiles, multi-Re.
Reads:
  ghia_u_sweep.csv
  ghia_v_sweep.csv
Expected column format:
  {vcol}_re{N}_jnl, {vcol}_re{N}_ghia  (with matching {ucol} column)
Writes:
  ghia_u_sweep.pdf / ghia_u_sweep.png
  ghia_v_sweep.pdf / ghia_v_sweep.png

Encoding:
  Colour → Reynolds number  (blue=100, red=400, green=1000)
  Style  → source           (solid line=JNLCFD, triangle markers=Ghia)
"""

import csv
import re
import os
import matplotlib.pyplot as plt
import matplotlib as mpl

# ── Palette ───────────────────────────────────────────────────
PALETTE = ["#0077bb", "#ee3333", "#22aa55", "#ff8800", "#aa33cc", "#009988"]

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


def try_float(value):
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def read_sweep(path, xcol, ycol):
    """
    Parse a multi-Re sweep CSV.  Detects Re numbers from headers of
    the form {ycol}_re{N}_jnl and returns a list of dicts:
        [{ re: int, jnl: [(x,y),...], ghia: [(x,y),...] }, ...]
    sorted by Re ascending.
    """
    with open(path, newline="") as f:
        reader = csv.DictReader(f)
        headers = reader.fieldnames or []

        re_numbers = sorted(
            int(m.group(1))
            for h in headers
            if (m := re.match(rf"{ycol}_re(\d+)_jnl", h))
        )

        data = {n: {"jnl": [], "ghia": []} for n in re_numbers}

        for row in reader:
            for n in re_numbers:
                xj = try_float(row.get(f"{xcol}_re{n}_jnl", ""))
                yj = try_float(row.get(f"{ycol}_re{n}_jnl", ""))
                if xj is not None and yj is not None:
                    data[n]["jnl"].append((xj, yj))

                xg = try_float(row.get(f"{xcol}_re{n}_ghia", ""))
                yg = try_float(row.get(f"{ycol}_re{n}_ghia", ""))
                if xg is not None and yg is not None:
                    data[n]["ghia"].append((xg, yg))

    return [{"re": n, **data[n]} for n in re_numbers]


def plot_sweep(path, xcol, ycol, xlabel, ylabel, title, legend_loc, legend_bbox=None):
    if not os.path.exists(path):
        print(f"Skipping {path} (not found)")
        return

    series = read_sweep(path, xcol, ycol)

    fig, ax = plt.subplots(figsize=(11.66, 7.28))

    for i, s in enumerate(series):
        colour = PALETTE[i % len(PALETTE)]

        if s["jnl"]:
            xs, ys = zip(*s["jnl"])
            ax.plot(xs, ys, color=colour, lw=2.0, zorder=4, label=f"$Re = {s['re']}$  (JNLCFD)")

        if s["ghia"]:
            xg, yg = zip(*s["ghia"])
            ax.scatter(xg, yg, color=colour, s=90, marker="^", zorder=5, label=f"$Re = {s['re']}$  (Ghia et al.)")

    ax.set_xlabel(xlabel)
    ax.set_ylabel(ylabel)
    ax.set_title(r"$\bf{" + title + r"}$")

    legend_kwargs = dict(
        loc=legend_loc,
        framealpha=0.9,
        edgecolor="#cccccc",
        handletextpad=0.6,
        borderpad=0.7,
        labelspacing=0.4,
    )
    if legend_bbox is not None:
        legend_kwargs["bbox_to_anchor"] = legend_bbox

    ax.legend(**legend_kwargs)
    ax.grid(True, color="#dddddd", linewidth=1.0, zorder=0)
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)

    out_stem = os.path.splitext(path)[0]
    plt.tight_layout()
    plt.savefig(out_stem + ".pdf", bbox_inches="tight")
    plt.savefig(out_stem + ".png", dpi=200, bbox_inches="tight")
    plt.close(fig)
    print(f"Saved {out_stem}.pdf / .png")


plot_sweep(
    path="ghia_u_sweep.csv",
    xcol="u",
    ycol="y",
    xlabel=r"$u \,/\, U_\mathrm{lid}$",
    ylabel=r"$y \,/\, H$",
    title=r"Lid\text{-}Driven\ Cavity\ -\ u\ Velocity\ Profile",
    legend_loc="lower right",
)

plot_sweep(
    path="ghia_v_sweep.csv",
    xcol="x",
    ycol="v",
    xlabel=r"$x \,/\, L$",
    ylabel=r"$v \,/\, U_\mathrm{lid}$",
    title=r"Lid\text{-}Driven\ Cavity\ -\ v\ Velocity\ Profile",
    legend_loc="lower left",
)
