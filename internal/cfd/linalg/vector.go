package linalg

type Vector []float32

func (v Vector) Wipe() {
	for i := range v {
		v[i] = 0.0
	}
}
