package main

import (
	"context"
	"fmt"
	"os"

	"github.com/Jedsonofnel/jnlcfd/internal/web"
)

func main() {
	ctx := context.Background()
	if err := web.Run(ctx, os.Args); err != nil {
		fmt.Fprintf(os.Stderr, "%s\n", err)
		os.Exit(1)
	}
}
