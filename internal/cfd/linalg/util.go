package linalg

func Dot2D(ax, ay, bx, by float64) float64 {
	return ax*bx + ay*by
}

type System struct {
	A *CSR
	B Vector
}

func (s System) Wipe() {
	s.A.Wipe()
	s.B.Wipe()
}
