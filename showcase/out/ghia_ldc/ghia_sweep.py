#!/usr/bin/env python3
"""
Ghia et al. lid-driven cavity validation — u and v profiles, multi-Re.
Reads ghia_u_sweep.csv and ghia_v_sweep.csv (same format), outputs
ghia_u_sweep.pdf/.png and ghia_v_sweep.pdf/.png.

Encoding:
  Colour → Reynolds number  (blue=100, red=400, green=1000)
  Style  → source           (solid line=JNLCFD, triangle markers=Ghia)
"""

import csv
import re
import os
import matplotlib.pyplot as plt
import matplotlib as mpl

# ── Palette (jnl.gp M.colour) ─────────────────────────────────
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


# ── CSV reader ────────────────────────────────────────────────
def read_sweep(path, xcol, ycol):
    """
    Parse a multi-Re sweep CSV.  Detects Re numbers from headers of
    the form {ycol}_re{N}_jnl and returns a list of dicts:
        [{ re: int, jnl: [(x,y),...], ghia: [(x,y),...] }, ...]
    sorted by Re ascending.  xcol/ycol are the column name prefixes,
    e.g. xcol="u", ycol="y" for the u-profile or xcol="x", ycol="v"
    for the v-profile.
    """
    with open(path, newline="") as f:
        reader = csv.DictReader(f)
        headers = reader.fieldnames or []

        re_numbers = []
        for h in headers:
            m = re.match(rf"{ycol}_re(\d+)_jnl", h)
            if m:
                re_numbers.append(int(m.group(1)))

        data = {n: {"jnl": [], "ghia": []} for n in re_numbers}

        for row in reader:
            for n in re_numbers:
                try:
                    x = float(row[f"{xcol}_re{n}_jnl"])
                    y = float(row[f"{ycol}_re{n}_jnl"])
                    data[n]["jnl"].append((x, y))
                except (ValueError, KeyError):
                    pass
                try:
                    xg = row.get(f"{xcol}_re{n}_ghia", "").strip()
                    yg = row.get(f"{ycol}_re{n}_ghia", "").strip()
                    if xg and yg:
                        data[n]["ghia"].append((float(xg), float(yg)))
                except (ValueError, KeyError):
                    pass

    return [{"re": n, **data[n]} for n in sorted(re_numbers)]


# Plot
def plot_sweep(
    csv_path,
    xcol,
    ycol,
    xlabel,
    ylabel,
    title,
    out_stem,
    legend_loc="best",
    legend_bbox=None,
):
    series = read_sweep(csv_path, xcol, ycol)

    fig, ax = plt.subplots(figsize=(11.66, 7.28))

    for i, s in enumerate(series):
        colour = PALETTE[i % len(PALETTE)]

        if s["jnl"]:
            xs, ys = zip(*s["jnl"])
            ax.plot(
                xs,
                ys,
                color=colour,
                lw=2.0,
                zorder=4,
                label=f"$Re = {s['re']}$  (JNLCFD)",
            )

        if s["ghia"]:
            xg, yg = zip(*s["ghia"])
            ax.scatter(
                xg,
                yg,
                color=colour,
                s=90,
                marker="^",
                zorder=5,
                label=f"$Re = {s['re']}$  (Ghia et al.)",
            )

    ax.set_xlabel(xlabel)
    ax.set_ylabel(ylabel)
    ax.set_title(r"$\bf{" + title + r"}$")

    legend_kwargs = {
        "loc": legend_loc,
        "framealpha": 0.9,
        "edgecolor": "#cccccc",
        "handletextpad": 0.6,
        "borderpad": 0.7,
        "labelspacing": 0.4,
    }

    if legend_bbox is not None:
        legend_kwargs["bbox_to_anchor"] = legend_bbox

    ax.legend(**legend_kwargs)

    ax.grid(True, color="#dddddd", linewidth=1.0, zorder=0)
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)

    plt.tight_layout()
    plt.savefig(out_stem + ".pdf", bbox_inches="tight")
    plt.savefig(out_stem + ".png", dpi=200, bbox_inches="tight")
    plt.close(fig)
    print(f"Saved {out_stem}.pdf / .png")


# ── Sweeps ────────────────────────────────────────────────────
sweeps = [
    dict(
        csv_path="ghia_u_sweep.csv",
        xcol="u",
        ycol="y",
        xlabel=r"$u \,/\, U_\mathrm{lid}$",
        ylabel=r"$y \,/\, H$",
        title=r"Lid\text{-}Driven\ Cavity\ -\ u\ Velocity\ Profile",
        out_stem="ghia_u_sweep",
        legend_loc="lower right",
    ),
    dict(
        csv_path="ghia_v_sweep.csv",
        xcol="x",
        ycol="v",
        xlabel=r"$x \,/\, L$",
        ylabel=r"$v \,/\, U_\mathrm{lid}$",
        title=r"Lid\text{-}Driven\ Cavity\ -\ v\ Velocity\ Profile",
        out_stem="ghia_v_sweep",
        legend_loc="center left",
        legend_bbox=(1.02, 0.5),
    ),
]

for s in sweeps:
    if os.path.exists(s["csv_path"]):
        plot_sweep(**s)
    else:
        print(f"Skipping {s['csv_path']} (not found)")
