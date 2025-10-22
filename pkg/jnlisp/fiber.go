package jnlisp

import (
	"strconv"
)

// per eval thread context
type fiber struct {
	stack       []frame
	maxDepth    int
	vm          *VM
	gensymCount int // for generating unique symbols
}

type frame struct {
	sexp   Sexp
	idx    int
	mapKey string
	op     opType
}

type opType int

const (
	opEval opType = iota
	opExpand
)

func (f *fiber) pushEval(sexp Sexp, idx int) {
	f.stack = append(f.stack, frame{
		sexp: sexp,
		idx:  idx,
		op:   opEval,
	})
}

func (f *fiber) pushEvalMapValue(value Sexp, key string) {
	f.stack = append(f.stack, frame{
		sexp:   value,
		idx:    -1,
		mapKey: key,
		op:     opEval,
	})
}

func (f *fiber) pushExpand(sexp Sexp, idx int) {
	f.stack = append(f.stack, frame{
		sexp: sexp,
		idx:  idx,
		op:   opExpand,
	})
}

func (f *fiber) pushExpandMapValue(value Sexp, key string) {
	f.stack = append(f.stack, frame{
		sexp:   value,
		idx:    -1,
		mapKey: key,
		op:     opEval,
	})
}

func (f *fiber) pop() {
	f.stack = f.stack[:len(f.stack)-1]
}

func (f *fiber) recursionLimitReached() bool {
	if len(f.stack) > f.maxDepth {
		return true
	}
	return false
}

func (f *fiber) gensym() Symbol {
	f.gensymCount++
	return Symbol("#tmp" + strconv.Itoa(f.gensymCount))
}

func (f *fiber) copyStack() []frame {
	clone := make([]frame, len(f.stack))
	copy(clone, f.stack)
	return clone
}
