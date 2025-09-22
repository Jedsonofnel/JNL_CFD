package geometry

import (
	"fmt"
)

type Rectangle struct {
	Height, Width float32
}

func (r Rectangle) EnforceContains(x, y float32) {
	if !(x >= 0 && x <= r.Width && y >= 0 && y <= r.Height) {
		panic(fmt.Sprintf("Point (%.2f, %.2f) does not fit in bounds [%.2f, %.2f]",
			x, y, r.Width, r.Height))
	}
}
