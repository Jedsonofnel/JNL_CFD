package linalg

func Dot2D(ax, ay, bx, by float32) float32 {
	return ax*bx + ay*by
}

type System struct {
	A Matrix
	B Vector
}

func (s System) Wipe() {
	s.A.Wipe()
	s.B.Wipe()
}
