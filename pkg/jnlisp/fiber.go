package jnlisp

import (
	"strconv"
	"strings"
)

// per eval thread context
type fiber struct {
	stack       []frame
	maxDepth    int
	gensymCount int // for generating unique symbols
	block       *Block
}

type frame struct {
	sexp Sexp
	idx  int
	op   opType
}

func (f frame) Type() string { return "jnlisp-frame" }
func (f frame) String() string {
	b := strings.Builder{}
	b.WriteString("> at: ")
	b.WriteString(f.op.String())
	b.WriteString(" ")
	b.WriteString(strconv.Itoa(f.idx))
	b.WriteString(": ")
	b.WriteString(f.sexp.String())
	return b.String()
}

type opType int

const (
	opExpand opType = iota
	opElaborate
	opEval
)

var opTypeDisplay = []string{"expand", "elaborate", "eval"}

func (o opType) String() string { return opTypeDisplay[o] }

func (f *fiber) push(sexp Sexp, idx int, op opType) {
	f.stack = append(f.stack, frame{
		sexp: sexp,
		idx:  idx,
		op:   op,
	})
}

func (f *fiber) pop() {
	f.stack = f.stack[:len(f.stack)-1]
}

func (f *fiber) updateCurrentFrame(sexp Sexp, idx int) {
	lastFrame := &f.stack[len(f.stack)-1]
	lastFrame.sexp = sexp
	lastFrame.idx = idx
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

func displayStack(stack []frame) string {
	b := strings.Builder{}
	b.WriteString("call stack: \n")

	frames := make([]string, 0, len(stack))
	for _, frame := range stack {
		frames = append([]string{frame.String()}, frames...)
	}

	b.WriteString(strings.Join(frames, "\n"))
	return b.String()
}
