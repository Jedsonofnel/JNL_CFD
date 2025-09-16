package web

import (
	"encoding/json"
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

func handlePeeks(_ *log.Logger, view *View) http.Handler {
	data := map[string]string{}

	return http.HandlerFunc(
		func(w http.ResponseWriter, r *http.Request) {
			view.Render(w, "peeks", data)
		},
	)
}

func handlePeekShow(_ *log.Logger, view *View) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		idString := r.PathValue("id")

		peekData := struct {
			Id   string         `json:"id"`
			Type string         `json:"type"`
			Data map[string]any `json:"data"`
		}{
			Id:   idString,
			Type: "structuredMeshDefinition",
			Data: map[string]any{"nx": 1, "ny": 20, "width": 1, "height": 0.8},
		}

		jsonData, _ := json.Marshal(peekData)
		view.Render(w, "peek", string(jsonData))
	})
}
