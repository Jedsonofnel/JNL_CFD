package jnlisp

func (f *fiber) eval(sexp Sexp, env *env) (Sexp, Error) {
	defer f.pop() // remove last frame from stack on return

	if len(f.stack) == 0 { // called top level without pushing to stack
		f.pushEval(sexp, 0)
	}

	if f.recursionLimitReached() {
		return nil, f.newErrRecursionLimitReached()
	}

	f.pushExpand(sexp, 0)
	sexp, err := f.expand(sexp, env)
	if err != nil {
		return nil, err
	}

	// ELABORATION

	// TCO LOOP
TCO:
	for {
		break TCO
	}

	return sexp, nil
}
