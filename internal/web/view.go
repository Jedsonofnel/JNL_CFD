//go:generate go run generate_assets.go

package web

import (
	"io/fs"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/cbroglie/mustache"
)

type View struct {
	layoutStore     map[string]*mustache.Template
	pageStore       map[string]*mustache.Template
	partialProvider mustache.PartialProvider
	layoutData      map[string]any
	fs              fs.FS
}

type FSPartialProvider struct {
	fs fs.FS
}

func (fp *FSPartialProvider) Get(name string) (string, error) {
	content, err := fs.ReadFile(fp.fs, name)
	if err != nil {
		return "", err
	}
	return string(content), err
}

func NewView() *View {
	templateFs, _ := fs.Sub(getFS(), "templates")

	partialFs, _ := fs.Sub(templateFs, "partials")
	fp := &FSPartialProvider{partialFs}

	layoutData := make(map[string]any)
	layoutData["timestamp"] = time.Now().UnixMilli()

	v := View{
		layoutStore:     make(map[string]*mustache.Template),
		pageStore:       make(map[string]*mustache.Template),
		partialProvider: fp,
		layoutData:      layoutData,
		fs:              templateFs,
	}

	return &v
}

func (v *View) LoadTemplates() error {
	pagesDir := filepath.Join("pages")
	if err := v.populateStore(v.pageStore, pagesDir); err != nil {
		return err
	}

	layoutsDir := filepath.Join("layouts")
	if err := v.populateStore(v.layoutStore, layoutsDir); err != nil {
		return err
	}

	return nil
}

func (v *View) populateStore(store map[string]*mustache.Template, dir string) error {
	return fs.WalkDir(v.fs, dir, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}

		if !d.IsDir() && strings.ToLower(filepath.Ext(path)) == ".html" {
			fileName := filepath.Base(path)
			nameWithoutExt := strings.TrimSuffix(fileName, filepath.Ext(fileName))

			content, err := fs.ReadFile(v.fs, path)
			if err != nil {
				return err
			}

			tmpl, err := mustache.ParseStringPartials(string(content), v.partialProvider)
			if err != nil {
				return err
			}

			store[nameWithoutExt] = tmpl
		}
		return nil
	})
}

func (v *View) Render(w http.ResponseWriter, name string, context any) error {
	layout := v.layoutStore["base"]
	data := struct{ Layout, Page any }{v.layoutData, context}
	err := v.pageStore[name].FRenderInLayout(w, layout, data)
	if err != nil {
		return err
	}
	return nil
}

func getFS() fs.FS {
	if os.Getenv("ENV") == "production" {
		return getEmbeddedFS() // This will be generated
	}
	return os.DirFS("./")
}
