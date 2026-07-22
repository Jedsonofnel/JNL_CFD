;;; (nabla fvm bcs) ; BC constructors

;; deps
(local {: assert-number : assert-oneof} (require :nabla.core.validation))

;;; Examples

;; BC set looks like
(comment {:phi {:north {:kind :dirichlet-s :value 5}
                :south {:kind :robin-s :a 3 :b 2 :c 1}
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
                :south (bc.robin-s 1 2 3)
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
  {:kind :dirichlet-s : value})

(fn neumann-s [grad-n]
  "Create a scalar neumann boundary condition descriptor"
  (assert-number grad-n "neumann-s grad-n")
  {:kind :neumann-s : grad-n})

(fn robin-s [a b c]
  "Create a scalar robin boundary condition descriptor"
  (assert-number a "robin-s a")
  (assert-number b "robin-s b")
  (assert-number c "robin-s c")
  {:kind :robin-s : a : b : c})

;; Vectors

(fn dirichlet-v [ux ?uy]
  "Create a vector dirichlet boundary condition descriptor"
  (let [uy (or ?uy ux)]
    (assert-number ux "dirichlet-v ux")
    (assert-number uy "dirichlet-v uy")
    {:kind :dirichlet-v : ux : uy}))

(fn neumann-v [ux-gn ?uy-gn]
  "Create a vector neumann boundary condition descriptor"
  (let [uy-gn (or ?uy-gn ux-gn)]
    (assert-number ux-gn "neumann-v ux-gn")
    (assert-number uy-gn "neumann-v uy-gn")
    {:kind :neumann-v : ux-gn : uy-gn}))

(fn nt-v [n-kind n-val t-kind t-val]
  (assert-oneof n-kind [:dirichlet :neumann] "nt-v n-kind")
  (assert-number n-val "nt-v n-val")
  (assert-oneof t-kind [:dirichlet :neumann] "nt-v t-kind")
  (assert-number t-val "nt-v t-val")
  "Create a normal-tangent boundary condition descriptor"
  {:kind :nt-v : n-kind : n-val : t-kind : t-val})

;; TODO - polymorphic

{: dirichlet-s : neumann-s : robin-s : dirichlet-v : neumann-v : nt-v}
