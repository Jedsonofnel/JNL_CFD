package geometry

import (
	"fmt"
	"github.com/Jedsonofnel/cfd-but-wasm/linalg"
)

type Rectangle struct {
	Height, Width float32
}

func (r Rectangle) EnforceContains(point linalg.Vec2) {
	if !(point.X >= 0 && point.X <= r.Width && point.Y >= 0 && point.Y <= r.Height) {
		panic(fmt.Sprintf("Point (%.2f, %.2f) does not fit in bounds [%.2f, %.2f]",
			point.X, point.Y, r.Width, r.Height))
	}
}
