package geometry

import (
	"github.com/Jedsonofnel/jnlcfd/pkg/jnlisp"
)

func init() {
	jnlisp.RegisterLibrary(jnlisp.Library{
		Name: "cfd/geometry",
		Bindings: map[string]jnlisp.ProcFunc{
			"structured-mesh": lispStructuredMesh,
		},
		Atoms: map[string]jnlisp.Atom{},
	})
}

type MeshDefinitionAtom struct{ Value MeshDefinition }

func (md MeshDefinitionAtom) Type() string   { return "cfd.MeshDefinition" }
func (md MeshDefinitionAtom) String() string { return "cfd.MeshDefinition" }
func (md MeshDefinitionAtom) ToJSON() map[string]any {
	return map[string]any{
		"type":  "cfd.MeshDefinition",
		"value": "INTERFACE TYPE",
		"repr":  md.String(),
	}
}

func lispStructuredMesh(args []jnlisp.Atom, kwargs jnlisp.Table) (jnlisp.Atom, error) {
	v := jnlisp.ValidateArgs(args, kwargs)
	nx, v := v.GetKeywordInt("nx")
	ny, v := v.GetKeywordInt("ny")
	width, v := v.GetKeywordFloat64("width")
	height, v := v.GetKeywordFloat64("height")

	v = v.ExpectNoMoreArgs()
	if err := v.Validate(); err != nil {
		return nil, err
	}

	sm := NewStructuredMesh(nx, ny, width, height)

	return MeshDefinitionAtom{sm}, nil
}
