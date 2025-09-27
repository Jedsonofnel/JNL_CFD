package web

import (
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

func handleWorkbooks(_ *log.Logger, view *View) http.Handler {
	data := map[string]string{}

	return http.HandlerFunc(
		func(w http.ResponseWriter, r *http.Request) {
			view.Render(w, "workbooks-index", data)
		},
	)
}

func handleWorkbookShow(_ *log.Logger, view *View) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		idString := r.PathValue("id")

		workbook, found := predefinedWorkbooks(idString)
		if !found {
			w.WriteHeader(http.StatusNotFound)
			view.Render(w, "404", map[string]string{"path": r.URL.Path, "return": "/workbooks"})
			return
		}

		view.Render(w, "workbook-show", map[string]any{
			"contents": workbook,
		})
	})
}
