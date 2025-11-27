//go:build !wasm

package main

import (
	"fmt"
	"log"

	"github.com/Jedsonofnel/jnlcfd/internal/cfd/geometry"
	"github.com/Jedsonofnel/jnlcfd/internal/cfd/nativedisp"
	"github.com/hajimehoshi/ebiten/v2"
)

var header string = `
       _       __________________ 
      (_)___  / / ____/ ____/ __ \
     / / __ \/ / /   / /_  / / / /
    / / / / / / /___/ __/ / /_/ / 
 __/ /_/ /_/_/\____/_/   /_____/  
/___/                             `

func main() {
	fmt.Println(header)
	fmt.Println("\ndisplaying mesh...")

	var db geometry.DomainBuilder
	db.AddPolygon(geometry.MakeRectangle(0, 0, 100, 100, "pcb", "outer"))
	db.AddPolygon(geometry.MakeRectangle(10, 10, 30, 30, "chip", "wall"))

	db.AddHole(geometry.MakeCircle(50, 50, 5, 32, "hole", "hole-wall"))

	domain, err := db.Build()
	if err != nil {
		log.Fatal(err)
	}

	mesh, err := geometry.MeshDomain(domain, "pzq30a10")
	if err != nil {
		log.Fatal(err)
	}

	viewer := nativedisp.NewMeshViewer(mesh, 800, 600)

	ebiten.SetWindowSize(640, 480)
	ebiten.SetWindowTitle("jnlCFD viewer")
	// Call ebiten.RunGame to start your game loop.
	if err := ebiten.RunGame(viewer); err != nil {
		log.Fatal(err)
	}
}
