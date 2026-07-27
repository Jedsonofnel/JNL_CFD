;;; (nabla fvm chasm) CHASM assembly for FVM procedures

(local {: valid : mangle : util : array : pool} (require :nabla.core))
(local bc (require :nabla.fvm.bc))
(local meshlib (require :nabla.mesh))
(local {: new-fvsys} (require :nabla.fvm.bindings))

;;; Vars

;; TODO assert-identifier on domain opts.domain name
;; TODO some sort of table spec assertion (ie so only recognised fields are allowed) for opts

;; Var construction
(fn scalar [name ?opts]
  "Create a scalar field-spec with a system"
  (valid.assert-identifier name "chasm scalar name")
  (when (?. ?opts :domain)
    (valid.assert-identifier ?opts.domain "chasm scalar opts.domain"))
  (let [opts (or ?opts {})]
    {: name
     :varkind :scalar
     :init opts.init
     :rank 0
     :has-sys? true
     :domain (or opts.domain :__default)}))

(fn scalar-arr [name ?opts]
  "Create a scalar array field-spec (no system)"
  (valid.assert-identifier name "chasm scalar-arr name")
  (when (?. ?opts :domain)
    (valid.assert-identifier ?opts.domain "chasm scalar-arr opts.domain"))
  (let [opts (or ?opts {})]
    {: name
     :varkind :scalar
     :init opts.init
     :rank 0
     :domain (or opts.domain :__default)
     :facewise? (or opts.facewise? opts.fw?)}))

(fn parse-vector-init [name ?init]
  (case ?init
    (where n (util.number? n)) [n n]
    (where [x y] (util.numbers? x y)) [x y]
    nil [0 0]
    _
    (error (string.format "vector '%s' init: expected nil, number or [x y] pair, got %s"
                          name ?init) 3)))

(fn vector [name ?opts]
  "Create a vector field-spec with a system"
  (valid.assert-identifier name "chasm vector name")
  (when (?. ?opts :domain)
    (valid.assert-identifier ?opts.domain "chasm vector opts.domain"))
  (let [opts (or ?opts {})
        domain (or opts.domain :__default)
        [init-x init-y] (parse-vector-init name opts.init)
        cname #(mangle.component name $1)
        x {:name (cname :x) :rank 0 : domain :init init-x :has-sys? true}
        y {:name (cname :y) :rank 0 : domain :init init-y :has-sys? true}]
    {: name
     :varkind :vector
     :init [init-x init-y]
     :rank 1
     :has-sys? true
     : domain
     : x
     : y}))

(fn vector-arr [name ?opts]
  "Create a vector array field-spec (no system)"
  (valid.assert-identifier name "chasm vector-arr name")
  (when (?. ?opts :domain)
    (valid.assert-identifier ?opts.domain "chasm vector-arr opts.domain"))
  (let [opts (or ?opts {})
        domain (or opts.domain :__default)
        facewise? (or opts.facewise? opts.fw?)
        [init-x init-y] (parse-vector-init name opts.init)
        cname #(mangle.component name $1)
        x {:name (cname :x) :init init-x : domain : facewise? :rank 0}
        y {:name (cname :y) :init init-y : domain : facewise? :rank 0}]
    {: name
     :varkind :vector
     :init [init-x init-y]
     :rank 1
     : domain
     : x
     : y
     : facewise?}))

;; Block construction
(fn block [name instructions ?opts]
  "Create a named program block-spec"
  (valid.assert-identifier name "chasm block name")
  (when (= (length instructions) 0)
    (error (string.format "Block '%s': instruction array must have at least one instruction"
                          name)))
  (let [opts (or ?opts {})]
    {: name
     : instructions
     :max-iters (or opts.max-iters 1)
     :convergence opts.convergence}))

;; Program construction

(fn get-components [v]
  "Recursively get components of var v into a flat list (kinda cursed and unecessary)"
  (if (< 0 v.rank)
      (util.concat-lists! (util.concat-lists! [v.x v.y]
                                              (or (get-components v.x) []))
                          (or (get-components v.y) []))
      nil))

;; Proof get-components works lol
(comment (let [v (vector :jedn)]
           (get-components v)))

(fn expand-vars-with-components! [var-map]
  "Add var components to var-map"
  (each [_ v (pairs var-map)]
    (when (< 0 v.rank)
      (each [_ cv (ipairs (get-components v))]
        (tset var-map cv.name cv)))))

;; Proof that expand-vars-with-components! works
(comment (let [s1 (scalar :s1)
               s2 (scalar :s2)
               v1 (vector :v1)
               v2 (vector :v2)
               vars {: s1 : s2 : v1 : v2}]
           (expand-vars-with-components! vars)
           vars))

;; Main entry point
(fn program [name var-list main-block]
  "Create a program-spec"
  (valid.assert-identifier name "chasm program name")
  (when (= (length var-list) 0)
    (error (string.format "Program '%s': var array must have at least one var")))
  (let [var-map {}
        var-map (collect [_ v (ipairs var-list) &into var-map]
                  (if (. var-map v.name)
                      (error (string.format "Program '%s': var '%s' appears at least twice in var array"
                                            name v.name))
                      (values v.name v)))
        domains (accumulate [domains {} _ v (ipairs var-list)]
                  (when (not (. domains v.domain))
                    (tset domains v.domain {:name v.domain})
                    domains))]
    (expand-vars-with-components! var-map)
    {: name :vars var-map : main-block : domains}))

(comment (program :someprogram [(scalar :s1) (vector :v1 {:domain :new})] nil))

;; Program compilation and allocation

(fn get-domain-vars [vars domain-name]
  "Get subset of vars map pertaining to the domain"
  (collect [vn v (pairs vars)]
    (if (= v.domain domain-name)
        (values vn v))))

(fn allocate-domain [domain-name mesh-spec bc-spec fields]
  "Allocate a domain: mesh, bcs, scratch pools and length diagonstics"
  (let [mesh (meshlib.resolve mesh-spec)
        {: warnings : bcs} (bc.resolve bc-spec fields (mesh:patches))
        num-cells (mesh:n_cells)
        num-faces (mesh:n_faces)]
    {: warnings
     :domains {domain-name {:name domain-name
                            : mesh
                            : bcs
                            : num-cells
                            : num-faces
                            :pool-cells (pool.new num-cells)
                            :pool-faces (pool.new num-faces)}}}))

;; IF length of program-spec domains is 1 (ie one domain) accept "raw" mesh-spec + bc-spec
;; Otherwise require {:domain1 mesh-spec1 :domain2 mesh-spec2} and ditto for bcs
(fn allocate-domains [{: domains : vars} mesh-spec bc-spec]
  "Allocates domain meshes and bcs, accepting single mesh and bc spec if only one domain"
  (let [domain-names (icollect [dn _ (pairs domains)] dn)]
    (if (= (length domain-names) 1)
        (let [dn (. domain-names 1)
              fields (get-domain-vars vars dn)]
          (allocate-domain dn mesh-spec bc-spec fields))
        (let [per-domain (icollect [dn _ (pairs domains)]
                           (allocate-domain dn mesh-spec bc-spec
                                            (get-domain-vars vars dn)))]
          {:warnings (util.concat-all :warnings per-domain)
           :domains (util.concat-all :domains per-domain)}))))

(fn allocate-arrays [domains vars]
  "Return map of varname: allocated array"
  (collect [name v (pairs vars)]
    (when (= v.rank 0) ; only allocate scalars
      (let [domain (. domains v.domain)]
        (values name
                (if v.facewise?
                    (array.new domain.num-faces v.init)
                    (array.new domain.num-cells v.init)))))))

(fn allocate-systems [domains vars]
  "Return map of varname: allocated fvsystem"
  (collect [name v (pairs vars)]
    (when (= v.rank 0)
      (let [domain (. domains v.domain)]
        (values name (if v.has-sys?
                         (new-fvsys domain.mesh)))))))

(fn compile [program-spec mesh-spec bc-spec]
  "Compile program into a runtime for execution"
  (let [;; domains hold mesh/bcs/pools/numcell
        {:warnings dwarnings : domains} (allocate-domains program-spec
                                                          mesh-spec bc-spec)
        arrays (allocate-arrays domains program-spec.vars)
        systems (allocate-systems domains program-spec.vars)]
    (when (not= nil (next dwarnings))
      (print (string.format "Compilation warnings for program '%s'\n%s"
                            program-spec.name (table.concat dwarnings "\n"))))
    {:name program-spec.name
     :main-block program-spec.main-block
     :vars program-spec.vars
     : domains
     : arrays
     : systems}))

;; Runtime accessors

(fn get-var [rt name]
  "Get var table from runtime"
  (or (. rt.vars name) (error (.. "unknown var '" name "'"))))

(fn get-sys [rt name]
  "Get system from runtime"
  (. rt.systems name))

(fn get-array [rt name]
  "Get array from runtime"
  (. rt.arrays name))

(fn get-const [rt name]
  "Get constant value from runtime"
  (. (. rt.consts name) :value))

(fn get-sys+mesh [rt name]
  "Get system and mesh according to variable name from runtime"
  (let [v (get-var rt name)
        domain (. rt.domains v.domain)]
    {:sys (get-sys rt name) :mesh domain.mesh}))

(fn get-sys+mesh+bcs [rt name]
  "Get system, mesh and bcs according to variable name from runtime"
  (let [v (get-var rt name)
        domain (. rt.domains v.domain)]
    {:sys (get-sys rt name) :mesh domain.mesh :bcs domain.bcs}))

(fn get-pool-cells [rt name]
  "Get cellwise scratch pool corresponding to name from runtime"
  (let [v (get-var rt name)] (. rt.domains v.domain :pool-cells)))

;; Virtual machine execution

(fn check-convergence [_pred _ctx]
  "Checks predicate tree against exec ctx and returns true/false"
  ;; TODO implement this
  false)

(fn run-outer-iter! [_rt _?block _?depth]
  (error "this is a forward declaration"))

;; TODO add to ctx when block is finished to allow step-outer! to check for that
(fn run-block! [rt block ctx depth]
  "Run a block's instructions"
  (each [_ inst (ipairs block.instructions)]
    (if inst.instructions
        (run-outer-iter! rt inst (+ 1 depth))
        (let [isa (require :nabla.fvm.instructions)
              instr-exec-fn (. isa inst.op :exec)
              record (instr-exec-fn rt ctx inst)]
          (when record (coroutine.yield record))))))

(fn run-outer-iter! [rt block ?depth ?iter]
  (let [iter (or ?iter 1)
        depth (or ?depth 1)
        ctx {:block-name block.name :depth (or ?depth 1) :iter (or ?iter 1)}]
    (run-block! rt block ctx depth)
    (if (or (check-convergence block.convergence ctx) (<= block.max-iters iter))
        ctx
        (run-outer-iter! rt block depth (+ 1 iter)))))

(fn add-defaults-to-result! [result]
  "Add default values to certain keys to result, like status"
  (when (not result.status)
    (set result.status :running)))

(fn step! [rt]
  "Run a single VM step (instruction or part of an instruction)"
  (when (not rt.co) ; build the coroutine idempotently
    (set rt.co (coroutine.create (fn []
                                   (let [final (run-outer-iter! rt
                                                                rt.main-block 1)]
                                     (set final.status :done)
                                     (coroutine.yield final))))))
  (let [(ok result) (coroutine.resume rt.co)]
    (if (not ok)
        {:status :error :error result}
        (do
          (add-defaults-to-result! result)
          result))))

(fn run-all! [rt] ; FOUND THE BUG - status is NOT included
  "Run all instructions until finished or error"

  (fn loop [result]
    (if (= result.status :running)
        (loop (step! rt))
        (if (= result.status :error)
            (error (.. "VM execution error: " result.error))
            result)))

  ;; run the loop recursively! (Abelson and Sussman would be proud)
  (loop (step! rt)))

{;; Var constructors
 : scalar
 : scalar-arr
 : vector
 : vector-arr
 : block
 : program
 : compile
 : step!
 : run-all!
 ;; Acessors
 : get-var
 : get-sys
 : get-array
 : get-const
 : get-sys+mesh
 : get-sys+mesh+bcs
 : get-pool-cells}
