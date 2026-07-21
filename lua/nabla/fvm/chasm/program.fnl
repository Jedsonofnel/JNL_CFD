;; (nabla fvm chasm program)

(local {: component} (require :nabla.core.mangle))
(local {: identifier} (require :nabla.core.validation))

;; Var object
(local Var {})
(set Var.__index Var)

(fn Var.__tostring [self] self.name)

(fn new-scalar-var [{:name domain-name} name init]
  "Creates a new scalar Var with name and init or 0"
  (setmetatable {: domain-name
                 : name
                 :rank 0
                 :kind :scalar
                 :has-sys? false
                 :facewise? false
                 :init (or init 0)} Var))

;; (new-scalar-var {:name :domain-name} :phi)

(fn new-vector-var [{:name domain-name} name init]
  "Create a new vector Var with name and init or [0 0]"
  (let [init (case init
               (where [x y] (and (= (type x) :number) (= (type y) :number))) [x
                                                                              y]
               (where n (= (type n) :number)) [n n]
               nil [0 0]
               _ (error "vector init: expected number or [x y] pair" 3))
        x (new-scalar-var {:name domain-name} (component name :x (. init 1)))
        y (new-scalar-var {:name domain-name} (component name :y (. init 2)))]
    (setmetatable {: domain-name
                   : name
                   :rank 1
                   :kind :vector
                   :has-sys? false
                   :facewise? false
                   : init
                   : x
                   : y} Var)))

;; (new-vector-var {:name :snarp} :U [1 2])

(fn Var.sys [self]
  "Mutate var to have a system"
  (set self.has-sys? true)
  self)

(fn Var.face [self]
  "Mutate var to be facewise"
  (set self.facewise? true)
  self)

;; TODO some functional equivalents?

(fn Var.residual_lt [self val]
  "Create predicate for residual < v"
  {:kind :lt :src :residual :key self.name : val})

(fn Var.residual_gt [self val]
  "Create predicate for residual > v"
  {:kind :lg :src :residual :key self.name : val})

;; TODO add more residuals

(fn new-constant [name value]
  "Create a new CHASM constant"
  (setmetatable {: name : value :rank 0 :kind :constant}
                {:__tostring (fn [self] self.name)}))

;; Domain object
(local Domain {})
(set Domain.__index Domain)

(fn new-domain [prog name]
  "Create a new CHASM domain"
  (setmetatable {: prog : name :vars {}} Domain))

(fn Domain.scalar [self name init]
  "Create a new scalar in the domain with name and init"
  (identifier name "CHASM scalar name")
  (let [v (new-scalar-var self name init)]
    (if (. self.prog.vars name)
        (error (string.format "var '%s' already exists" name 2))
        (do
          (tset self.prog.vars name v)
          v))))

(fn domain-add-vector! [domain vname vinit]
  "Add a new vector to domain with name and init"
  (identifier vname "CHASM vector name")
  (let [v (new-vector-var domain vname vinit)]
    (if (. domain.prog.vars vname)
        (error (string.format "var '%s' already exists" vname 3))
        (do
          (tset domain.prog.vars vname v)
          (tset domain.prog.vars v.x.name v.x)
          (tset domain.prog.vars v.y.name v.y)
          v))))

(fn Domain.vector [self name init]
  "Add a new vector with name and init"
  (domain-add-vector! self name init))

(fn domain-bind! [domain mesh bcs]
  "Bind mesh and boundary conditions to the domain"
  (assert mesh "mesh required for binding")
  (assert bcs "bccs required for binding")
  (let [[warnings errors] (bcs:validate mesh)]
    (when (> (length warnings) 0)
      (error (string.format "BC errors: \n%s" (table.concat errors "\n  "))))
    (when (> (length errors) 0)
      (error (string.format "BC warnings: \n%s" (table.concat warnings "\n  ")))))
  (set domain.mesh mesh)
  (set domain.bcs bcs)
  (let [n-cells (mesh:n_cells)
        n-faces (mesh:n_faces)]
    (set domain.n-cells n-cells)
    (set domain.n-faces n-faces)
    (set domain.pool-cells (new-pool n-cells))
    (set domain.pool-faces (new-pool n-faces)))
  domain)

(fn Domain.bind [self mesh bcs]
  "Bind mesh and boundary conditions to self"
  (domain-bind! self mesh bcs))

;; Program object
(local Program {})
(set Program.__index Program)

(fn new-chasm-program [name]
  "Create a new CHASM program object"
  (setmetatable {: name
                 :domains {}
                 :vars {}
                 :consts {}
                 :ISA nil
                 ; TODO implement ISA
                 } Program))

(fn program-bind! [program mesh bcs]
  "Bind mesh and bcs to default program domain"
  (let [default (or (. program.domains :default)
                    (error "cannot bind to default domain as no variables declared onto it"
                           2))]
    (domain-bind! default mesh bcs)
    program))

(fn allocate-var! [v {: n-cells : n-faces : mesh}]
  "Allocate a var given a domain"
  (when (= v.rank 0)
    (if v.facewise?
        (set v.vec (new-vec n-faces v.init))
        (do
          (set v.vec (new-vec n-cells v.init))
          (when v.has-sys?
            (set v.fvsys (new-fvsys mesh)))))
    v))

(fn program-allocate! [program]
  "Allocate vars in program"
  (each [_ v (pairs program.vars)]
    (let [domain (. program.domains v.domain-name)]
      (allocate-var! v domain))))

{:new new-chasm-program}
