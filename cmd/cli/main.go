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
    
    domain, err := db.Build()
    if err != nil {
        log.Fatal(err)
    }

    // Debug: check if region center is set correctly
    fmt.Printf("Region center: %+v\n", domain.Polygons[0].Center())
    
    // Use more reasonable triangle size
    mesh, err := geometry.MeshDomain(domain, "pq30a500")
    if err != nil {
        log.Fatal(err)
    }

    // Debug: print mesh stats
    fmt.Printf("Mesh: %d vertices, %d connections\n", 
        len(mesh.Vertices), len(mesh.Connections))

	viewer := nativedisp.NewMeshViewer(mesh, 800, 600)

	ebiten.SetWindowSize(640, 480)
	ebiten.SetWindowTitle("jnlCFD viewer")
	// Call ebiten.RunGame to start your game loop.
	if err := ebiten.RunGame(viewer); err != nil {
		log.Fatal(err)
	}
}
