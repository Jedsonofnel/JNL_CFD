set datafile separator ','
set key top left
set xlabel 'x'
set ylabel 'phi'
set title 'Convection-Diffusion (Pe=1)'
set grid

set terminal pngcairo size 800,600
set output 'results.png'

plot 'results.csv' skip 1 using 1:2 with linespoints pt 7 title 'CDS', \
     '' skip 1 using 1:3 with linespoints pt 5 title 'UDS', \
     '' skip 1 using 1:4 with lines lw 2 title 'Analytical'
