package web

import (
	"log"
	"net/http"
)

func addRoutes(mux *http.ServeMux, logger *log.Logger, view *View) {
	assets := http.FileServer(http.Dir("assets/"))
	mux.Handle("/assets/", http.StripPrefix("/assets/", assets))

	// pages
	mux.Handle("/", handleHomeShow(logger, view))

	// api
	mux.Handle("/api/up", handleUp(logger))
}
