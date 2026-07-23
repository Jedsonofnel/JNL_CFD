;; (nabla core validation) ; validation library

(fn assert-typeof [val t label]
  "Asserts val has type t, errors with label if not"
  (when (not= (type val) t)
    (error (string.format "%s: expected %s, got %s" label t (type val)) 3)))

(fn assert-number [val ?label]
  "Assert val has typeof number, errors with optional label if not"
  (when (not= (type val) :number)
    (error (string.format "%s: expected number, got %s" (or ?label :error)
                          (type val)))))

(fn assert-positive-integer [val ?label]
  "Assert val is a positive integer, errors with optinal label if not"
  (when (or (not= (type val) :number) (< val 0) (not= (math.floor val) val))
    (error (string.format "%s: expected positive integer, got %s (%s)"
                          (or ?label :error) val (type val)))))

(fn assert-identifier [s label]
  "Asserts val is a valid nabla identifier, errors with label if not"
  (assert-typeof s :string label)
  (when (s:match "^__")
    (error (string.format "%s: names starting with __ are reserved: %s" label s)
           3))
  (when (not (s:match "^[%a_][%a%d_]*$"))
    (error (string.format "%s: not a valid identifier: %s" label s) 3)))

(fn assert-oneof [val options label]
  "Asserts val is oneof options, errors with label if not"
  (let [found (accumulate [found false _ opt (ipairs options) &until found]
                (= val opt))]
    (when (not found)
      (error (string.format "%s: expected one of [%s], got '%s'" label
                            (table.concat options "|") val) 3))))

{: assert-typeof
 : assert-number
 : assert-positive-integer
 : assert-identifier
 : assert-oneof}
