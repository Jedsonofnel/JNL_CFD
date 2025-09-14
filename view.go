package main

import (
	"github.com/cbroglie/mustache"
	"io/fs"
	"net/http"
	"path/filepath"
	"strings"
	"time"
)

type View struct {
	layoutStore     map[string]*mustache.Template
	pageStore       map[string]*mustache.Template
	partialProvider mustache.PartialProvider
	layoutData      map[string]any
}

func NewView() *View {
	fp := mustache.FileProvider{}

	layoutData := make(map[string]any)
	layoutData["timestamp"] = time.Now().UnixMilli()

	v := View{
		layoutStore:     make(map[string]*mustache.Template),
		pageStore:       make(map[string]*mustache.Template),
		partialProvider: &fp,
		layoutData:      layoutData,
	}

	return &v
}

func (v *View) LoadTemplates() error {
	// TODO: populate my filepath partial provider

	pagesDir := filepath.Join("templates", "pages")
	if err := populateStore(v.pageStore, pagesDir, v.partialProvider); err != nil {
		return err
	}

	layoutsDir := filepath.Join("templates", "layouts")
	if err := populateStore(v.layoutStore, layoutsDir, v.partialProvider); err != nil {
		return err
	}

	return nil
}

func populateStore(store map[string]*mustache.Template, dir string, pp mustache.PartialProvider) error {
	return filepath.WalkDir(dir,
		func(path string, d fs.DirEntry, err error) error {
			if err != nil {
				return err
			}

			if !d.IsDir() && strings.ToLower(filepath.Ext(path)) == ".html" {
				fileName := filepath.Base(path)
				nameWithoutExt := strings.TrimSuffix(fileName, filepath.Ext(fileName))

				tmpl, err := mustache.ParseFilePartials(path, pp)
				if err != nil {
					return err
				}

				store[nameWithoutExt] = tmpl
				println(nameWithoutExt)
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
