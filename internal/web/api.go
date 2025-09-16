package web

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
)

func encode[T any](w http.ResponseWriter, status int, v T) error {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(v); err != nil {
		return fmt.Errorf("encode json: %w", err)
	}
	return nil
}

func decode[T any](r *http.Request) (T, error) {
	var v T
	if err := json.NewDecoder(r.Body).Decode(&v); err != nil {
		return v, fmt.Errorf("decode json: %w", err)
	}
	return v, nil
}

func handleAPIUp(logger *log.Logger) http.Handler {
	return http.HandlerFunc(
		func(w http.ResponseWriter, r *http.Request) {
			if err := encode(w, http.StatusOK, "service up"); err != nil {
				logger.Printf("Error encoding 'service up' in handleUp: %s", err)
				handleJSONError(w, "Something went wrong our end", http.StatusInternalServerError)
			}
		},
	)
}

func handleAPIPeeksIndex(logger *log.Logger) http.Handler {
	envelope := struct {
		Id   string         `json:"id"`
		Type string         `json:"type"`
		Data map[string]any `json:"data"`
	}{
		Id:   "1234",
		Type: "structuredMeshDefinition",
		Data: map[string]any{"nx": 500, "ny": 200},
	}

	data := []any{envelope}

	return http.HandlerFunc(
		func(w http.ResponseWriter, r *http.Request) {
			if err := encode(w, http.StatusOK, data); err != nil {
				logger.Printf("Error encoding peeks data in handleGetPeeks: %s", err)
				handleJSONError(w, "Something went wrong our end", http.StatusInternalServerError)
			}
		},
	)
}

func handleJSONError(w http.ResponseWriter, message string, status int) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(map[string]string{"error": message})
}
