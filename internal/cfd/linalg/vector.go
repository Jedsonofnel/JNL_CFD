package linalg

type Vector []float32

func (v Vector) Wipe() {
	for i := range v {
		v[i] = 0.0
	}
}

type Vec2 struct{ X, Y float32 }
