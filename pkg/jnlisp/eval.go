package jnlisp

func (f *fiber) eval(sexp Sexp, env *env) (Sexp, Error) {
	defer f.pop() // remove last frame from stack on return

	if len(f.stack) == 0 { // called top level without pushing to stack
		f.push(sexp, 0, opEval)
	}

	if f.recursionLimitReached() {
		return nil, f.newErrRecursionLimitReached()
	}

	f.push(sexp, 0, opExpand)
	sexp, err := f.expand(sexp, env)
	if err != nil {
		return nil, err
	}

	// ELABORATION
	f.push(sexp, 0, opElaborate)
	sexp, err = f.elaborate(sexp)
	if err != nil {
		return nil, err
	}

	// TCO LOOP
TCO:
	for {
		break TCO
	}

	return sexp, nil
}
