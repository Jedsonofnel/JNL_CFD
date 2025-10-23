package jnlisp

import (
	"strconv"
)

// per eval thread context
type fiber struct {
	stack       []frame
	maxDepth    int
	gensymCount int // for generating unique symbols
	block       *Block
}

type frame struct {
	sexp   Sexp
	idx    int
	mapKey string
	op     opType
}

type opType int

const (
	opExpand opType = iota
	opElaborate
	opEval
)

func (f *fiber) push(sexp Sexp, idx int, op opType) {
	f.stack = append(f.stack, frame{
		sexp: sexp,
		idx:  idx,
		op:   op,
	})
}

func (f *fiber) pushMapValue(value Sexp, key string, op opType) {
	f.stack = append(f.stack, frame{
		sexp:   value,
		idx:    -1,
		mapKey: key,
		op:     op,
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
