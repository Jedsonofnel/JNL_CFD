.PHONY: plot clean

plot: results.png
	xdg-open results.png

results.png: results.csv plot.gp
	gnuplot plot.gp

results.csv: main.go
	go run . > results.csv 2> debug.txt

clean:
	rm -f results.csv results.png debug.txt
