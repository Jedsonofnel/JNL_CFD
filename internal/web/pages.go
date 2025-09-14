package web

import (
	"log"
	"net/http"
)

func handleHome(_ *log.Logger, view *View) http.Handler {
	data := map[string]string{"name": "Jed"}

	return http.HandlerFunc(
		func(w http.ResponseWriter, r *http.Request) {
			view.Render(w, "home", data)
		},
	)
}

func handlePeeks(_  *log.Logger, view *View) http.Handler {
	data := map[string]string{}

	return http.HandlerFunc(
		func(w http.ResponseWriter, r *http.Request) {
			view.Render(w, "peeks", data)
		},
	)
}
