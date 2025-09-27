package web

import (
	"io/fs"
	"path/filepath"
	"strings"
)

func predefinedWorkbooks(name string) (string, bool) {
	filesystem := getFS()
	var content []byte

	workbooksDir := filepath.Join("jnlisp")

	err := fs.WalkDir(filesystem, workbooksDir, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}

		if !d.IsDir() && strings.ToLower(filepath.Ext(path)) == ".jnl" {
			fileName := filepath.Base(path)
			nameWithoutExt := strings.TrimSuffix(fileName, filepath.Ext(fileName))

			b, err := fs.ReadFile(filesystem, path)
			if err != nil {
				return err
			}

			if nameWithoutExt == name {
				content = b
			}
		}
		return nil
	})

	if err != nil || content == nil {
		return "", false
	}

	trimmed := strings.Trim(string(content), " ")

	return trimmed, true
}
