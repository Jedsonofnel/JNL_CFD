package main

import (
	"log"
	"net/http"
)

func handleHomeShow(_ *log.Logger, view *View) http.Handler {
	data := map[string]string{"name": "Jed"}

	return http.HandlerFunc(
		func(w http.ResponseWriter, r *http.Request) {
			view.Render(w, data)
		},
	)
}
