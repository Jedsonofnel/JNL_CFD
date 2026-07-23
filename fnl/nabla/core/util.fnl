;;; (nabla util) ; A collection of utilites

;; Predicates

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

(fn string? [val]
  "Return true if val is string"
  (= (type val) :string))

;; Some list manipulation goodness

(fn concat-all [key results]
  "Concatenate all lists in results with key"
  (let [out []]
    (each [_ r (ipairs results)]
      (let [keyvals (. r key)]
        (when keyvals ; gracefully skip when doesn't exist
          (each [_ item (ipairs keyvals)] (table.insert out item)))))
    out))

;; Example usage
(comment (let [results [{:key [1 2 3]} {:key [4 5 6]} {:key [7 8 10]}]]
           (concat-all :key results)))

;; Without the right keys
(comment (let [results-missing-key [{:key [1 2 3]} {:bad-key [4 5 6]}]]
           (concat-all :key results-missing-key)))

(fn concat-lists! [l1 l2]
  "Concatenate l2 into and after l1"
  (icollect [_ val (ipairs l2) &into l1] val))

;; Example usage
(comment (let [one-list [1 2 3 4]
               two-list [5 6 7 8]]
           (concat-lists! one-list two-list)))

{: number?
 : numbers?
 : positive-integer?
 : string?
 : concat-all
 : concat-lists!}
