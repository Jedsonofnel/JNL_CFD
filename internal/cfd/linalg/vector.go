package linalg

import (
	"github.com/chewxy/math32"
)

type Vector []float32

func (v Vector) Wipe() {
	for i := range v {
		v[i] = 0.0
	}
}

type Vec2 struct{ X, Y float32 }

func (v Vec2) Magnitude() float32 {
	return math32.Sqrt(v.X*v.X + v.Y*v.Y)
}

func (v Vec2) Normalize() Vec2 {
	mag := v.Magnitude()
	return Vec2{v.X / mag, v.Y / mag}
}

func (v Vec2) Dot(other Vec2) float32 {
	return v.X*other.X + v.Y*other.Y
}

func (v Vec2) UnitCCWNormal() Vec2 {
	return Vec2{v.Y, -v.X}.Normalize()
}
