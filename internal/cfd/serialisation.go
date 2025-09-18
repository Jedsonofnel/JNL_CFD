package cfd

type DefinitionEnvelope struct {
	Name   string `json:"name"`
	Type   string `json:"type"`
	Family string `json:"family"`
	Data   any    `json:"data"`
}

// TODO: some function for de-serialising here maybe
