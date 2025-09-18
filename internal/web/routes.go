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
	mux.Handle("GET /viewports", handleViewports(logger, view))
	mux.Handle("GET /viewports/{id}", handleViewportShow(logger, view))

	// api
	mux.Handle("GET /api/up", handleAPIUp(logger))
	mux.Handle("GET /api/peeks", handleAPIPeeksIndex(logger))
}
