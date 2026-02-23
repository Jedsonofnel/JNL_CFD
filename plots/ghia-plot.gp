#!/usr/bin/env gnuplot
#
# Usage:
#   gnuplot -e "re=100" ghia_plot.gp
#
# Expects: ghia_re<re>.csv in current directory

if (!exists("re")) re = 100

infile = sprintf("ghia_re%d.csv", re)

set terminal qt size 1200,500 enhanced font "Helvetica,12" persist
set datafile separator ","

set style line 1 lc rgb "#2563EB" lw 2 dt 1          # sim: blue line
set style line 2 lc rgb "#DC2626" pt 7 ps 1.4 lw 1.5  # ghia: red circles

set multiplot layout 1,2 margins 0.08,0.97,0.12,0.88 spacing 0.1

# --- Left: Ux along vertical centreline ---
set title sprintf("Re = %d - Ux along x = 0.5", re) font ",14"
set xlabel "Ux"
set ylabel "y"
set xrange [*:*]
set yrange [0:1]
set grid lc rgb "#E5E7EB" lw 0.5
set key top left font ",11"

plot infile index 0 using 2:1 with lines ls 1 title "Simulation", \
     infile index 1 using 2:1 with points ls 2 title "Ghia et al."

# --- Right: Uy along horizontal centreline ---
set title sprintf("Re = %d - Uy along y = 0.5", re) font ",14"
set xlabel "x"
set ylabel "Uy"
set xrange [0:1]
set yrange [*:*]
set key top right font ",11"

plot infile index 2 using 1:2 with lines ls 1 title "Simulation", \
     infile index 3 using 1:2 with points ls 2 title "Ghia et al."

unset multiplot
