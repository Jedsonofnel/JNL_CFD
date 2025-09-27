//go:build ignore

package main

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
)

func main() {
	// Copy the directories
	if err := copyDir("../../templates", "templates"); err != nil {
		panic(err)
	}
	if err := copyDir("../../assets", "assets"); err != nil {
		panic(err)
	}
	if err := copyDir("../../jnlisp", "jnlisp"); err != nil {
		panic(err)
	}

	// Generate the embed file
	content := `package web

import (
	"embed"
	"io/fs"
)

//go:embed templates assets jnlisp
var embeddedAssets embed.FS

func getEmbeddedFS() fs.FS {
	return embeddedAssets
}
`
	if err := os.WriteFile("assets.go", []byte(content), 0644); err != nil {
		panic(err)
	}

	fmt.Println("Generated assets.go with copied files")
}

func copyDir(src, dst string) error {
	return filepath.WalkDir(src, func(path string, d os.DirEntry, err error) error {
		if err != nil {
			return err
		}

		relPath, _ := filepath.Rel(src, path)
		dstPath := filepath.Join(dst, relPath)

		if d.IsDir() {
			return os.MkdirAll(dstPath, 0755)
		}

		srcFile, err := os.Open(path)
		if err != nil {
			return err
		}
		defer srcFile.Close()

		os.MkdirAll(filepath.Dir(dstPath), 0755)
		dstFile, err := os.Create(dstPath)
		if err != nil {
			return err
		}
		defer dstFile.Close()

		_, err = io.Copy(dstFile, srcFile)
		return err
	})
}
