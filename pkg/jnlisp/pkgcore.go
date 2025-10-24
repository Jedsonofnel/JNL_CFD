package jnlisp

var corePkg = &Package{
	Name: "core",
	Bindings: map[string]Sexp{
		"+": add,
	},
}

var add = Native{
	name:  "+",
	arity: DefaultArity(),
	fn: func(args []Sexp, f *fiber) (Sexp, Error) {
		av := ValidateArgs(args, DefaultArity(), f, "+")
		numbers := GetVariadic[Number](av)
		if err := av.Validate(); err != nil {
			return Nil{}, err
		}

		if len(numbers) == 0 {
			return Int(0), nil
		}

		targetType := PromoteNumbersTo(numbers...)

		switch targetType {
		case "int":
			sum := 0
			for _, num := range numbers {
				val, _ := num.ToInt()
				sum += val
			}
			return Int(sum), nil
		case "float64":
			sum := 0.0
			for _, num := range numbers {
				val, _ := num.ToFloat64()
				sum += val
			}
			return Float(sum), nil
		default:
			var sum complex128
			for _, num := range numbers {
				sum += num.ToComplex128()
			}
			return Complex(sum), nil
		}
	},
}
