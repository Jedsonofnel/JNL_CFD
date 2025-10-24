package jnlisp

var corePkg = &Package{
	Name: "core",
	Bindings: map[string]Sexp{
		"+": add,
		"*": multiply,
		"-": subtract,
		"/": divide,
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

var multiply = Native{
	name:  "*",
	arity: DefaultArity(),
	fn: func(args []Sexp, f *fiber) (Sexp, Error) {
		av := ValidateArgs(args, DefaultArity(), f, "*")
		numbers := GetVariadic[Number](av)
		if err := av.Validate(); err != nil {
			return Nil{}, err
		}

		if len(numbers) == 0 {
			return Int(1), nil
		}

		targetType := PromoteNumbersTo(numbers...)

		switch targetType {
		case "int":
			product := 1
			for _, num := range numbers {
				val, _ := num.ToInt()
				product *= val
			}
			return Int(product), nil
		case "float64":
			product := 1.0
			for _, num := range numbers {
				val, _ := num.ToFloat64()
				product *= val
			}
			return Float(product), nil
		default:
			var product complex128
			for _, num := range numbers {
				product += num.ToComplex128()
			}
			return Complex(product), nil
		}
	},
}

var subtractArity = Arity{Positional: []string{"a"}, Variadic: "rest"}
var subtract = Native{
	name:  "-",
	arity: subtractArity,
	fn: func(args []Sexp, f *fiber) (Sexp, Error) {
		av := ValidateArgs(args, subtractArity, f, "-")

		a := GetArg[Number](av)
		numbers := GetVariadic[Number](av)
		if err := av.Validate(); err != nil {
			return Nil{}, err
		}

		allNums := []Number{a}
		targetType := PromoteNumbersTo(append(allNums, numbers...)...)

		if len(numbers) == 0 {
			switch targetType {
			case "int":
				val, _ := a.ToInt()
				return Int(-val), nil
			case "float64":
				val, _ := a.ToFloat64()
				return Float(-val), nil
			default:
				return Complex(-a.ToComplex128()), nil
			}
		}

		switch targetType {
		case "int":
			result, _ := a.ToInt()
			for _, num := range numbers {
				val, _ := num.ToInt()
				result -= val
			}
			return Int(result), nil
		case "float64":
			result, _ := a.ToFloat64()
			for _, num := range numbers {
				val, _ := num.ToFloat64()
				result -= val
			}
			return Float(result), nil
		default:
			result := a.ToComplex128()
			for _, num := range numbers {
				result -= num.ToComplex128()
			}
			return Complex(result), nil
		}
	},
}

var divideArity = Arity{Positional: []string{"a"}, Variadic: "denoms"}
var divide = Native{
	name:  "/",
	arity: divideArity,
	fn: func(args []Sexp, f *fiber) (Sexp, Error) {
		av := ValidateArgs(args, divideArity, f, "/")

		a := GetArg[Number](av)
		denoms := GetVariadic[Number](av)
		if err := av.Validate(); err != nil {
			return Nil{}, err
		}

		allNums := []Number{a}
		targetType := PromoteNumbersTo(append(allNums, denoms...)...)

		switch targetType {
		case "int":
			aInt, _ := a.ToInt()
			if len(denoms) == 0 {
				if aInt == 0 {
					return Nil{}, f.newErrDivisionByZero()
				}
				return Int(1 / aInt), nil
			}
			result := aInt
			for _, d := range denoms {
				val, _ := d.ToInt()
				if val == 0 {
					return Nil{}, f.newErrDivisionByZero()
				}
				result /= val
			}
			return Int(result), nil
		case "float64":
			aFloat, _ := a.ToFloat64()
			if len(denoms) == 0 {
				if aFloat == 0 {
					return Nil{}, f.newErrDivisionByZero()
				}
				return Float(1 / aFloat), nil
			}
			result := aFloat
			for _, d := range denoms {
				val, _ := d.ToFloat64()
				if val == 0 {
					return Nil{}, f.newErrDivisionByZero()
				}
				result /= val
			}
			return Float(result), nil
		default:
			result := a.ToComplex128()
			if len(denoms) == 0 {
				if result == 0 {
					return Nil{}, f.newErrDivisionByZero()
				}
				return Complex(1 / result), nil
			}
			for _, d := range denoms {
				dComplex := d.ToComplex128()
				if dComplex == 0 {
					return Nil{}, f.newErrDivisionByZero()
				}
				result /= dComplex
			}
			return Complex(result), nil
		}
	},
}
