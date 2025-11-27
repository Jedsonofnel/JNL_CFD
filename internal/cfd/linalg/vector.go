package linalg

type Vector []float64

func (v Vector) Wipe() {
	for i := range v {
		v[i] = 0.0
	}
}

