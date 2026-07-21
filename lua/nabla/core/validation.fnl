;; (nabla core validation) ; validation library

(fn typeof [val t label]
  "Asserts val has type t, errors with label if not"
  (when (not= (type val) t)
    (error (string.format "%s: expected %s, got %s" label t (type val)) 3)))

(fn identifier [s label]
  "Asserts val is a valid nabla identifier, errors with label if not"
  (typeof s :string label)
  (when (s:match "^__")
    (error (string.format "%s: names starting with __ are reserved: %s" label s)
           3))
  (when (not (s:match "^[%a_][%a%d_]*$"))
    (error (string.format "%s: not a valid identifier: %s" label s) 3)))

(fn oneof [val options label]
  "Asserts val is oneof options, errors with label if not"
  (let [found (accumulate [found false _ opt (ipairs options) &until found]
                (= val opt))]
    (when (not found)
      (error (string.format "%s: expected one of [%s], got '%s'" label
                            (table.concat options "|") val) 3))))

{: typeof : identifier : oneof}
