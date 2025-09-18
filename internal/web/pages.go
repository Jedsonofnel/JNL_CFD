package web

import (
	"github.com/Jedsonofnel/jnlcfd/internal/cfd"
	"log"
	"net/http"
)

func handleHome(_ *log.Logger, view *View) http.Handler {
	return http.HandlerFunc(
		func(w http.ResponseWriter, r *http.Request) {
			if r.URL.Path != "/" {
				w.WriteHeader(http.StatusNotFound)
				view.Render(w, "404", map[string]string{"path": r.URL.Path})
				return
			}

			view.Render(w, "home", nil)
		},
	)
}

func handleViewports(_ *log.Logger, view *View) http.Handler {
	data := map[string]string{}

	return http.HandlerFunc(
		func(w http.ResponseWriter, r *http.Request) {
			view.Render(w, "viewports-index", data)
		},
	)
}

func handleViewportShow(_ *log.Logger, view *View) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		idString := r.PathValue("id")
		viewport, found := predefinedViewports[idString]

		if !found {
			w.WriteHeader(http.StatusNotFound)
			view.Render(w, "404", map[string]string{"path": r.URL.Path, "return": "/viewports"})
			return
		}

		view.Render(w, "viewport-show", map[string]any{
			idString: viewport,
			"name":   viewport.Name,
			"family": viewport.Family,
		})
	})
}

// Viewports

var predefinedViewports = map[string]cfd.DefinitionEnvelope{
	"structured-mesh": {
		Name:   "Structured Mesh",
		Type:   "structuredMeshDefinition",
		Family: "mesh",
		Data:   cfd.SampleStructuredMesh(),
	},
	"passive-transport-scenario": {
		Name:   "Passive Transport",
		Type:   "passiveTransportScenario",
		Family: "scenario",
		Data:   cfd.SampleStructuredMesh(),
	},
}
