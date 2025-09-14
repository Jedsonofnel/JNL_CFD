package web

import (
	"context"
	"flag"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
)

func Run(_ context.Context, args []string) error {
	env := os.Getenv("ENV")
	if env == "" {
		env = "development"
	}

	fs := flag.NewFlagSet(args[0], flag.ExitOnError)
	var (
		port = fs.String("port", "8000", "Port to bind to")
		host = fs.String("host", getDefaultHost(env), "Host to bind to")
	)
	fs.Parse(args[1:])

	logger, err := setupLogger(env)
	if err != nil {
		return fmt.Errorf("failed to setup logger: %w", err)
	}

	view := NewView()
	if err = view.LoadTemplates(); err != nil {
		return fmt.Errorf("failed to load templates: %w", err)
	}

	srv := NewServer(logger, view)
	addr := net.JoinHostPort(*host, *port)

	logger.Printf("Server starting on http://%s (env: %s)", addr, env)
	return http.ListenAndServe(addr, srv)
}

func NewServer(logger *log.Logger, view *View) http.Handler {
	mux := http.NewServeMux()
	addRoutes(mux, logger, view)

	var handler http.Handler = mux
	// TODO: middleware handling like auth
	return handler
}

func setupLogger(env string) (*log.Logger, error) {
	if env == "production" {
		if err := os.MkdirAll("logs", 0755); err != nil {
			return nil, err
		}

		file, err := os.OpenFile("logs/production.log", os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0666)
		if err != nil {
			return nil, err
		}

		// Don't defer file.Close() here - logger needs to keep writing to it
		return log.New(file, "[PROD] ", log.LstdFlags|log.Lshortfile), nil
	}

	return log.New(os.Stdout, "[DEV] ", log.LstdFlags), nil
}

func getDefaultHost(env string) string {
	if env == "production" {
		return "0.0.0.0"
	}
	return "localhost"
}
