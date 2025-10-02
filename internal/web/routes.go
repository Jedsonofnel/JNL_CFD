package web

import (
	"io/fs"
	"log"
	"net/http"
)

func addRoutes(mux *http.ServeMux, logger *log.Logger, view *View) {
	assetsFS, _ := fs.Sub(getFS(), "assets")
	assets := http.FileServer(http.FS(assetsFS))
	mux.Handle("GET /assets/", http.StripPrefix("/assets/", assets))

	// pages
	mux.Handle("GET /", handleHome(logger, view))
	mux.Handle("GET /fyp-proposal", handleFYPProposal(logger, view))
	mux.Handle("GET /workbooks", handleWorkbooks(logger, view))
	mux.Handle("GET /workbooks/{id}", handleWorkbookShow(logger, view))

	// api
	mux.Handle("GET /api/up", handleAPIUp(logger))
}
