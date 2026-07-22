;; (nabla fvm chasm program)

;; deps
(local {: component} (require :nabla.core.mangle))
(local {: assert-identifier} (require :nabla.core.validation))
(local array (require :nabla.core.array))
(local pool (require :nabla.core.pool))
(local {: numbers?} (require :nabla.util))
(local {: new-fvsys} (require :nabla.fvm.bindings))

;; Simplest type of thing - a constant
(fn new-constant [name value]
  "Create a new CHASM constant"
  (setmetatable {: name : value :rank 0 :kind :constant}
                {:__tostring (fn [self] self.name)}))

;; Var object
(local Var {})
(set Var.__index Var)

(fn Var.__tostring [self] self.name)

(fn new-scalar-var [{:name domain-name} name init opts]
  "Creates a new scalar Var with name and init or 0"
  (let [opts (or opts {})
        has-sys? (or (. opts :has-sys?) false)
        facewise? (or (. opts :facewise?) false)
        init (or init 0)]
    (setmetatable {: domain-name
                   : name
                   :rank 0
                   :kind :scalar
                   : has-sys?
                   : facewise?
                   : init} Var)))

;; (new-scalar-var {:name :domain-name} :phi)

(fn new-vector-var [{:name domain-name} name init opts]
  "Create a new vector Var with name and init or [0 0]"
  (let [init (case init
               (where [x y] (numbers? x y)) [x y]
               (where n (= (type n) :number)) [n n]
               nil [0 0]
               _ (error "vector init: expected number or [x y] pair" 3))
        x (new-scalar-var {:name domain-name} (component name :x (. init 1)))
        y (new-scalar-var {:name domain-name} (component name :y (. init 2)))
        opts (or opts {})
        has-sys? (or (. opts :has-sys?) false)
        facewise? (or (. opts :facewise?) false)]
    (setmetatable {: domain-name
                   : name
                   :rank 1
                   :kind :vector
                   : has-sys?
                   : facewise?
                   : init
                   : x
                   : y} Var)))

;; explict var variant constructors

(fn new-scalar-reg [domain name init]
  "Creates a new cellwise scalar register"
  (new-scalar-var domain name init {:has-sys? false :facewise? false}))

(fn new-scalar-reg-fw [domain name init]
  "Creates a new facewise scalar reg"
  (new-scalar-var domain name init {:has-sys? false :facewise? true}))

(fn new-scalar-prog [domain name init]
  "Creates a new scalar prognostic field (has system)"
  (new-scalar-var domain name init {:has-sys? true :facewise? false}))

(fn new-vector-reg [domain name init]
  "Creates a new cellwise vector register"
  (new-vector-var domain name init {:has-sys? false :facewise? false}))

(fn new-vector-reg-fw [domain name init]
  "Creates a new facewise vector register"
  (new-vector-var domain name init {:has-sys? false :facewise? true}))

(fn new-vector-prog [domain name init]
  "Creates a new vector prognostic field (has system)"
  (new-vector-var domain name init {:has-sys? true :facewise? false}))

;; Predicates from vars

(fn Var.residual_lt [self val]
  "Create predicate for residual < v"
  {:kind :lt :src :residual :key self.name : val})

(fn Var.residual_gt [self val]
  "Create predicate for residual > v"
  {:kind :lg :src :residual :key self.name : val})

;; TODO add more predicates

;; Domain object
(local Domain {})
(set Domain.__index Domain)

(fn new-domain [prog name]
  "Create a new CHASM domain"
  (setmetatable {: prog : name :vars {}} Domain))

;; Var creation and addition to domain

(fn exists-in-prog? [prog name]
  (or (. prog.consts name) (. prog.vars name)))

(fn assert-new-to-prog [prog name]
  (when (exists-in-prog? prog name)
    (error (string.format "name '%s' already exists in the program" name) 3)))

(fn domain-add-scalar-reg! [domain name init]
  "Add a cellwise scalar register to domain"
  (assert-identifier name "CHASM scalar name")
  (assert-new-to-prog domain.prog name)
  (let [reg (new-scalar-reg domain name init)]
    (tset domain.prog.vars name reg)
    reg))

(fn domain-add-scalar-reg-fw! [domain name init]
  "Add a facewise scalar register to domain"
  (assert-identifier name "CHASM scalar name")
  (assert-new-to-prog domain.prog name)
  (let [reg (new-scalar-reg-fw domain name init)]
    (tset domain.prog.vars name reg)
    reg))

(fn domain-add-scalar-prog! [domain name init]
  "Add a scalar prognostic field to domain"
  (assert-identifier name "CHASM scalar name")
  (assert-new-to-prog domain.prog name)
  (let [field (new-scalar-prog domain name init)]
    (tset domain.prog.vars name field)
    field))

(fn domain-add-vector-reg! [domain name init]
  "Add a cellwise vector register to domain"
  (assert-identifier name "CHASM vector name")
  (assert-new-to-prog domain.prog name)
  (let [reg (new-vector-reg domain name init)]
    (tset domain.prog.vars name reg)
    (tset domain.prog.vars reg.x.name reg.x)
    (tset domain.prog.vars reg.y.name reg.y)
    reg))

(fn domain-add-vector-reg-fw! [domain name init]
  "Add a facewise vector register to domain"
  (assert-identifier name "CHASM vector name")
  (assert-new-to-prog domain.prog name)
  (let [reg (new-vector-reg-fw domain name init)]
    (tset domain.prog.vars name reg)
    (tset domain.prog.vars reg.x.name reg.x)
    (tset domain.prog.vars reg.y.name reg.y)
    reg))

(fn domain-add-vector-prog! [domain name init]
  "Add a vector prognostic field to domain"
  (assert-identifier name "CHASM vector name")
  (assert-new-to-prog domain.prog name)
  (let [field (new-vector-prog domain name init)]
    (tset domain.prog.vars name field)
    (tset domain.prog.vars field.x.name field.x)
    (tset domain.prog.vars field.y.name field.y)
    field))

(fn Domain.scalar_reg [self name init]
  "Add a new scalar registry to domain"
  (domain-add-scalar-reg! self name init))

(fn Domain.scalar_reg_fw [self name init]
  "Add a new facewise scalar registry to domain"
  (domain-add-scalar-reg-fw! self name init))

(fn Domain.scalar_prog [self name init]
  "Add a new scalar prognostic field to domain"
  (domain-add-scalar-prog! self name init))

(fn Domain.vector_reg [self name init]
  "Add a new vector registry to domain"
  (domain-add-vector-reg! self name init))

(fn Domain.vector_reg_fw [self name init]
  "Add a new facewise vector registry to domain"
  (domain-add-vector-reg-fw! self name init))

(fn Domain.vector_prog [self name init]
  "Add a new vector prognostic field to domain"
  (domain-add-vector-prog! self name init))

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
    (set domain.pool-cells (pool.new n-cells))
    (set domain.pool-faces (pool.new n-faces)))
  domain)

(fn Domain.bind [self mesh bcs]
  "Bind mesh and boundary conditions to self"
  (domain-bind! self mesh bcs))

;; Program object
(local Program {})
(set Program.__index Program)

(fn new-program [name]
  "Create a new CHASM program object"
  (setmetatable {: name
                 :domains {}
                 :vars {}
                 :consts {}
                 :ISA (require :nabla.fvm.chasm.isa)} Program))

(fn program-get-or-create-default! [{: domains &as prog}]
  "Get or create the default domain from a program"
  (or domains.default (let [d (new-domain prog :default)]
                        (set domains.default d)
                        d)))

(fn program-add-const! [prog name value]
  "Add a named constant var to a program"
  (assert-identifier name "program constant name")
  (assert-new-to-prog prog name)
  (let [constant (new-constant name value)]
    (tset prog.consts name constant)
    constant))

;; TODO make this dispatch against whether .prog exists to accept domain OR prog
(fn add-scalar-reg! [prog name init]
  "Add a cellwise scalar registry to program default domain"
  (domain-add-scalar-reg! (program-get-or-create-default! prog) name init))

(fn add-scalar-reg-fw! [prog name init]
  "Add a facewise scalar registry to program default domain"
  (domain-add-scalar-reg-fw! (program-get-or-create-default! prog) name init))

(fn add-scalar-prog! [prog name init]
  "Add a prognostic scalar field to program default domain"
  (domain-add-scalar-prog! (program-get-or-create-default! prog) name init))

(fn add-vector-reg! [prog name init]
  "Add a cellwise vector registry to program default domain"
  (domain-add-vector-reg! (program-get-or-create-default! prog) name init))

(fn add-vector-reg-fw! [prog name init]
  "Add a facewise vector registry to program default domain"
  (domain-add-vector-reg-fw! (program-get-or-create-default! prog) name init))

(fn add-vector-prog! [prog name init]
  "Add a prognostic vector field to program default domain"
  (domain-add-vector-prog! (program-get-or-create-default! prog) name init))

(fn program-get-var [{: vars : prog-name} v]
  "Get a variable from a program by a variable object or string"
  (case v
    (where {: name} (and (= (type name) :string) (. vars name))) (. vars name)
    (where name (and (= (type name) :string) (. vars name))) (. vars name)
    _ (error (string.format "could not find var '%s' in program '%s'" v
                            prog-name))))

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
        (set v.array (array.new n-faces v.init))
        (do
          (set v.array (array.new n-cells v.init))
          (when v.has-sys?
            (set v.fvsys (new-fvsys mesh)))))
    v))

(fn program-allocate! [program]
  "Allocate vars in program"
  (each [_ v (pairs program.vars)]
    (let [domain (. program.domains v.domain-name)]
      (allocate-var! v domain))))

(fn program-write-main! [program cb iters]
  "Creates a new main block and passes to cb function for construction"
  (let [iters (or iters 1)
        {:new new-block} (require :nabla.fvm.chasm.block)
        main (new-block program :main iters)]
    (cb main)
    (set program.main-block main)
    main))

;; Program methods

(fn Program.scalar_reg [self name init]
  "Add a cellwise scalar registry to the program's default domain"
  (domain-add-scalar-reg! (program-get-or-create-default! self) name init))

(fn Program.scalar-reg-fw! [self name init]
  "Add a facewise scalar registry to the program's default domain"
  (domain-add-scalar-reg-fw! (program-get-or-create-default! self) name init))

(fn Program.scalar-prog! [self name init]
  "Add a prognostic scalar field to the program's default domain"
  (domain-add-scalar-prog! (program-get-or-create-default! self) name init))

(fn Program.vector_reg [self name init]
  "Add a cellwise vector registry to the program's default domain"
  (domain-add-vector-reg! (program-get-or-create-default! self) name init))

(fn Program.vector-reg-fw! [self name init]
  "Add a facewise vector registry to the program's default domain"
  (domain-add-vector-reg-fw! (program-get-or-create-default! self) name init))

(fn Program.vector-prog! [self name init]
  "Add a prognostic vector field to the program's default domain"
  (domain-add-vector-prog! (program-get-or-create-default! self) name init))

(fn Program.const [self name value]
  "Add a named constant to the program"
  (program-add-const! self name value))

(fn Program.get_var [self v]
  "Get a variable from program from a Var object or string"
  (program-get-var self v))

(fn Program.bind [self mesh bcs]
  "Bind mesh and bcs to default program domain"
  (program-bind! self mesh bcs))

;; Exported public entrypoint

{:new new-program
 : program-write-main!
 :allocate! program-allocate!
 : program-get-var
 : add-scalar-reg!
 : add-scalar-reg-fw!
 : add-scalar-prog!
 : add-vector-reg!
 : add-vector-reg-fw!
 : add-vector-prog!}
