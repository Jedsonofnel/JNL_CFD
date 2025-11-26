//go:build !wasm

package main

import (
	"fmt"
	"log"

	"github.com/Jedsonofnel/jnlcfd/internal/cfd/geometry"
	"github.com/Jedsonofnel/jnlcfd/internal/cfd/nativedisp"
	"github.com/hajimehoshi/ebiten/v2"
)

func main() {
	fmt.Println(`
       _       __________________ 
      (_)___  / / ____/ ____/ __ \
     / / __ \/ / /   / /_  / / / /
    / / / / / / /___/ __/ / /_/ / 
 __/ /_/ /_/_/\____/_/   /_____/  
/___/                             `)

	fmt.Println("\ndisplaying mesh...")

	domain := geometry.NewDomain()
	outer := geometry.NewRectangle(0, 0, 100, 100)
	bottomLeft := geometry.NewRectangle(2.5, 2.5, 45, 45)
	topLeft := geometry.NewRectangle(2.5, 52.5, 45, 45)
	bottomRight := geometry.NewRectangle(52.5, 2.5, 45, 45)
	topRight := geometry.NewRectangle(52.5, 52.5, 45, 45)

	if err := domain.AddShape(outer, "pcb", "outer"); err != nil {
		log.Fatal(err)
	}
	if err := domain.AddShape(bottomLeft, "chip", "inner"); err != nil {
		log.Fatal(err)
	}
	if err := domain.AddShape(topLeft, "chip", "inner"); err != nil {
		log.Fatal(err)
	}
	if err := domain.AddShape(bottomRight, "chip", "inner"); err != nil {
		log.Fatal(err)
	}
	if err := domain.AddShape(topRight, "chip", "inner"); err != nil {
		log.Fatal(err)
	}

	viewer := nativedisp.NewViewer(domain, 800, 600)

	ebiten.SetWindowSize(640, 480)
	ebiten.SetWindowTitle("jnlCFD viewer")
	// Call ebiten.RunGame to start your game loop.
	if err := ebiten.RunGame(viewer); err != nil {
		log.Fatal(err)
	}
}
