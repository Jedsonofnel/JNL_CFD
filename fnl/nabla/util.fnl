;; (nabla util) ; A collection of utilites

(fn number? [val]
  "Returns true if val is a number"
  (= (type val) :number))

(fn numbers? [...]
  "Returns true if all arguments are numbers"
  (accumulate [res true _ val (ipairs [...]) &until (not res)]
    (number? val)))

(fn positive-integer? [val]
  "Returns true if val is a positive integer"
  (and (number? val) (< 0 val) (= val (math.floor val))))

{: number? : numbers? : positive-integer?}
