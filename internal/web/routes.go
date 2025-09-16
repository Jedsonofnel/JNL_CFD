package web

import (
	"log"
	"net/http"
)

func addRoutes(mux *http.ServeMux, logger *log.Logger, view *View) {
	assets := http.FileServer(http.Dir("assets/"))
	mux.Handle("GET /assets/", http.StripPrefix("/assets/", assets))

	// pages
	mux.Handle("GET /", handleHome(logger, view))
	mux.Handle("GET /peeks", handlePeeks(logger, view))
	mux.Handle("GET /peeks/{id}", handlePeekShow(logger, view))

	// api
	mux.Handle("GET /api/up", handleAPIUp(logger))
	mux.Handle("GET /api/peeks", handleAPIPeeksIndex(logger))
}
