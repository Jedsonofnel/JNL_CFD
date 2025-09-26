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
	mux.Handle("GET /workbooks", handleWorkbooks(logger, view))
	mux.Handle("GET /workbooks/{id}", handleWorkbookShow(logger, view))

	// api
	mux.Handle("GET /api/up", handleAPIUp(logger))
}
