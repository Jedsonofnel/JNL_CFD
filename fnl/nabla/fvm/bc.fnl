;;; (nabla fvm bcs) ; BC constructors

;; deps
(local {: assert-number : assert-oneof} (require :nabla.core.validation))
(local util (require :nabla.core.util))

;;; Examples

;; BC set looks like
(comment {:phi {:north {:kind :dirichlet-s :value 5}
                :south {:kind :robin :a 3 :b 2 :c 1}
                :east {:kind :neumann-s :grad-n 9}
                :__default {:kind :neumann-s :grad-n 0}}
          :U {:north {:kind :dirichlet-v :ux 5 :uy 4}
              :south {:kind :neumann-v :ux-gn 4 :uy-gn 0}
              :west {:kind :nt-v
                     :n-kind :neumann
                     :n-val 1
                     :t-kind :neumann
                     :t-val 1}
              :__default {:kind :neumann-v :ux-gn 4 :uy-gn 5}}})

;; Or with constructors (different values to above)
(comment {:phi {:north (bc.dirichlet-s 5)
                :south (bc.robin 1 2 3)
                :east (bc.neumann-s 9)
                :__default (bc.neumann-s 0)}
          :U {:north (bc.dirichlet-v 5 4)
              :south (bc.neumann-v 4 0)
              :west (bc.nt-v :dirichlet 0 :neumann 1)
              :__default (bc.neumann-v 0)}})

;;; BC descriptor functions

;; Scalars

(fn dirichlet-s [value]
  "Create a scalar dirichlet boundary condition descriptor"
  (assert-number value "dirichlet-s value")
  {:kind :dirichlet-s :rank 0 : value})

(fn neumann-s [grad-n]
  "Create a scalar neumann boundary condition descriptor"
  (assert-number grad-n "neumann-s grad-n")
  {:kind :neumann-s :rank 0 : grad-n})

;; Robin is always scalar - no '-s' discrimination needed
(fn robin [a b c]
  "Create a scalar robin boundary condition descriptor"
  (assert-number a "robin a")
  (assert-number b "robin b")
  (assert-number c "robin c")
  {:kind :robin :rank 0 : a : b : c})

;; Vectors

(fn dirichlet-v [ux ?uy]
  "Create a vector dirichlet boundary condition descriptor"
  (let [uy (or ?uy ux)]
    (assert-number ux "dirichlet-v ux")
    (assert-number uy "dirichlet-v uy")
    {:kind :dirichlet-v :rank 1 : ux : uy}))

(fn neumann-v [ux-gn ?uy-gn]
  "Create a vector neumann boundary condition descriptor"
  (let [uy-gn (or ?uy-gn ux-gn)]
    (assert-number ux-gn "neumann-v ux-gn")
    (assert-number uy-gn "neumann-v uy-gn")
    {:kind :neumann-v :rank 1 : ux-gn : uy-gn}))

(fn nt-v [n-kind n-val t-kind t-val]
  (assert-oneof n-kind [:dirichlet :neumann] "nt-v n-kind")
  (assert-number n-val "nt-v n-val")
  (assert-oneof t-kind [:dirichlet :neumann] "nt-v t-kind")
  (assert-number t-val "nt-v t-val")
  "Create a normal-tangent boundary condition descriptor"
  {:kind :nt-v :rank 1 : n-kind : n-val : t-kind : t-val})

;; Polymorphic (by rank)

(fn dirichlet [ux ?uy]
  "Create a rank-polymorphic dirichlet boundary condition descriptor"
  (if ?uy ; if both are given it MUST be a vector
      (dirichlet-v ux ?uy)
      (do
        (assert-number ux "dirichlet ux")
        {:kind :dirichlet-poly :poly? true :value ux})))

(fn neumann [ux-gn ?uy-gn]
  "Create a rank-polymorphic neumann boundary condition descriptor"
  (if ?uy-gn
      (neumann-v ux-gn ?uy-gn)
      (do
        (assert-number ux-gn "neumann ux-gn")
        {:kind :neumann-poly :poly? true :grad-n ux-gn})))

(fn nograd []
  "Create a zero-gradient boundary condition descriptor"
  (neumann 0))

;; Validation

(fn validate-bc-rank [field patch-name bc]
  "Validate BC against field rank, nil if OK, error string if not"
  (when (and (not bc.poly?) (not= field.rank bc.rank))
    (string.format "field '%s' (rank %d): BC '%s' on patch '%s' is rank %d"
                   field.name field.rank bc.kind patch-name bc.rank)))

(fn validate-bc-patch-exists [field patch-name patches]
  "Validate the bc patch name is a valid  patch, nil if OK, error string if not"
  (when (and (not= patch-name :__default) (not (. patches patch-name)))
    (string.format "field '%s': unknown patch '%s' in BC set" field.name
                   patch-name)))

(fn validate-bc-field [field bc-map patches]
  "Validates BC to make sure ranks are correct (error) and checks all patches are set"
  (if (not bc-map)
      {:errors [(string.format "BCs not set for field %s" field.name)]
       :warnings []}
      {:errors (util.concat-lists! ; collect errors from two error producing functions together
                                   (icollect [patch-name bc (pairs bc-map)]
                                     (validate-bc-rank field patch-name bc))
                                   (icollect [patch-name _ (pairs bc-map)]
                                     (validate-bc-patch-exists field patch-name
                                                               patches)))
       :warnings (icollect [patch-name _ (pairs patches)]
                   (if (and (not (. bc-map patch-name))
                            (not (. bc-map :__default)))
                       (string.format "field '%s': patch '%s' uncovered, implicitly nograd"
                                      field.name patch-name)))}))

(fn validate [bcs fields patches]
  "Validate BCs returning errors and warnings"
  (let [per-field (icollect [field-name field (pairs fields)]
                    (validate-bc-field field (. bcs field-name) patches))]
    {:errors (util.concat-all :errors per-field)
     :warnings (util.concat-all :warnings per-field)}))

;; Resolution

(fn resolve-poly [rank bc-desc]
  "Resolve a polymorphic bc-desc"
  (case bc-desc
    {:kind :dirichlet-poly : value} (if (= rank 0) (dirichlet-s value)
                                        (= rank 1) (dirichlet-v value value)
                                        (error "resolve-poly: unsupported rank"))
    {:kind :neumann-poly : grad-n} (if (= rank 0) (neumann-s grad-n) (= rank 1)
                                       (neumann-v grad-n grad-n)
                                       (error "resolve-poly: unsupported rank"))))

(fn resolve-bc-field [field bc-map patches]
  "Create a new bc-map with every patch accounted for, no polymorphism and no default"
  (let [default (. bc-map :__default)]
    (collect [patch-name _ (pairs patches)]
      patch-name
      (let [bc-desc (. bc-map patch-name)]
        (if (not bc-desc) default ; default if doesn't exist
            bc-desc.poly? (resolve-poly field.rank bc-desc)
            bc-desc ; as-is if neither
            )))))

(fn resolve [bcs fields patches]
  "Validates and then resolves BCs"
  (let [{: errors : warnings &as validation-results} (validate bcs fields
                                                               patches)]
    (if (not= (length errors) 0)
        validation-results
        (let [resolved-bcs (collect [field-name field (pairs fields)]
                             field-name
                             (resolve-bc-field field (. bcs field-name) patches))]
          {: warnings :bcs resolved-bcs}))))

{:DEFAULT :__default
 : dirichlet-s
 : neumann-s
 : robin
 : dirichlet-v
 : neumann-v
 : nt-v
 : neumann
 : dirichlet
 : nograd
 : validate
 : resolve}
