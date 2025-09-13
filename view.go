package main

import (
	"github.com/cbroglie/mustache"
	"net/http"
)

type View struct {
	layoutStore     map[string]*mustache.Template
	pageStore       map[string]*mustache.Template
	partialProvider mustache.PartialProvider
}

func NewView() *View {
	fp := mustache.FileProvider{}

	v := View{
		layoutStore:     make(map[string]*mustache.Template),
		pageStore:       make(map[string]*mustache.Template),
		partialProvider: &fp,
	}

	return &v
}

func (v *View) LoadTemplates() error {
	tmpl, err := mustache.ParseStringPartials("<h1>Hello, {{name}}</h1>", v.partialProvider)
	if err != nil {
		return err
	}

	v.pageStore["home"] = tmpl
	return nil
}

func (v *View) Render(w http.ResponseWriter, context any) error {
	err := v.pageStore["home"].FRender(w, context)
	if err != nil {
		return err
	}
	return nil
}
