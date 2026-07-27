;;; (nabla fvm instructions) ; instruction set for CHASM

(local fvmb (require :nabla.fvm.bindings))
(local chasm (require :nabla.fvm.chasm))
(local {: util} (require :nabla.core))

;;; Helpers

(fn resolve-const [k]
  "Takes a constant that could be a table, string or number and returns string or number"
  (case k
    {:varkind :const : name} name
    (where s (util.string? s)) s
    (where num (util.number? num)) num
    nil 1
    _ (error (string.format "cannot resolve %s as a constant" k))))

(fn resolve-rt-const [rt k]
  "Takes a constant (string/number) and resolves to a number using the runtime"
  (case k
    (where num (util.number? num)) num
    (where s (util.string? s)) (chasm.get-const rt s)
    _ (error (string.format "cannot resolve %s as a constant" k))))

(fn resolve-scalar [v]
  "Takes a string/table and returns string"
  (case v
    {:varkind :scalar :has-sys? true : name} name
    (where s (util.string? s)) s
    _ (error (string.format "cannot resolve %s as a scalar" v))))

(fn make-instr [op-name build-fn str-fn exec-fn]
  "Bundle build/str/exec under one name; calling it builds + tags + pretty-prints"
  (let [entry {:build build-fn :str str-fn :exec exec-fn :op op-name}]
    (setmetatable entry {:__call (fn [_ ...]
                                   (let [instr (build-fn ...)]
                                     (set instr.op op-name)
                                     (setmetatable instr {:__tostring str-fn})
                                     instr))})))

;;; Some constants for pretty display purposes

(local ASM-NAMES {:laplacian-k :LAPK
                  :sys-reset-s :SYSR
                  :bc-close-s :BCCS
                  :krylov-s :KRYL})

(fn simple-instr-str [op-name ...]
  (let [arg-strs (icollect [_ a (ipairs [...])]
                   (tostring a))
        op-asm-name (or (. ASM-NAMES op-name) "????")]
    (string.format "%s %s" op-asm-name (table.concat arg-strs " "))))

;;; Implicit FVM operators

;; Laplacian

(fn lapk-build [phi gamma-k]
  "Apply laplacian to phi system with constant gamma"
  (let [gamma (resolve-const gamma-k)
        field (resolve-scalar phi)]
    {: field : gamma}))

(fn lapk-str [{: field : gamma}]
  "Pretty string for laplacian-k instruction"
  (simple-instr-str :laplacian-k field gamma))

(fn lapk-exec [rt _ctx {: field : gamma}]
  "Execute laplacian-k instruction"
  (let [gamma (resolve-rt-const rt gamma)
        {: sys : mesh} (chasm.get-sys+mesh rt field)]
    (fvmb.laplacian-k! sys mesh gamma)
    {:instr-name :laplacian-k : field : gamma}))

(local laplacian-k (make-instr :laplacian-k lapk-build lapk-str lapk-exec))

;;; Boundary conditions

(fn bccs-build [field]
  (let [field (resolve-scalar field)]
    {: field}))

(fn bccs-str [{: field}]
  (simple-instr-str :bc-close-s field))

(fn close-dirichlet-s! [sys mesh patch-name {: name} {: value}]
  (fvmb.patch-s-close-d! sys mesh patch-name value)
  {:instr-name :close-dirichlet-s :field name : value : patch-name})

(fn close-neumann-s! [sys mesh patch-name {: name} {: grad-n}]
  (fvmb.patch-s-close-n! sys mesh patch-name grad-n)
  {:instr-name :close-neumann-s :field name : grad-n : patch-name})

(fn close-robin! [sys mesh patch-name {: name} {: a : b : c}]
  (fvmb.patch-s-close-r! sys mesh patch-name a b c)
  {:instr-name :close-robin :field name : a : b : c : patch-name})

(local bc-close-table {:dirichlet-s close-dirichlet-s!
                       :neumann-s close-neumann-s!
                       :robin close-robin!})

(fn bccs-exec [rt _ctx {: field}]
  "Close BCs for every patch on field's mesh, yielding once per patch"
  (let [{: sys : mesh : bcs} (chasm.get-sys+mesh+bcs rt field)
        field-spec (. bcs field)]
    (each [patch-name _ (pairs (mesh:patches))]
      (let [spec (or (. field-spec patch-name) (. field-spec :__default))
            close-fn (. bc-close-table spec.bckind)
            result (close-fn sys mesh patch-name field spec)]
        (coroutine.yield result)
        nil))))

(local bc-close-s (make-instr :bc-close-s bccs-build bccs-str bccs-exec))

;;; Linear Algebra

(fn sysr-build [field]
  "Reset lienar algebra system for scalar field"
  (let [field (resolve-scalar field)]
    {: field}))

(fn sysr-str [{: field}]
  "Pretty string for sys-reset-s instruction"
  (simple-instr-str :sys-reset-s field))

(fn sysr-exec [rt _ctx {: field}]
  (let [sys (chasm.get-sys rt field)]
    (sys:reset)
    {:instr-name :sys-reset-s : field}))

(local sys-reset-s (make-instr :sys-reset-s sysr-build sysr-str sysr-exec))

;; Krylov [KRYL] - chunky old  instruction
(fn kryl-build [field ?opts]
  (let [field (resolve-scalar field)
        opts (or ?opts {})]
    {: field : opts}))

(fn kryl-str [{: field : opts}]
  (simple-instr-str :krylov-s field (or opts.solver :bicgstab-dilu)))

(fn make-solver [solver-name sys phi pool-cells tol restart]
  (case (solver-name:lower)
    :cg-jac (fvmb.new-solver-cg-jac sys phi tol pool-cells)
    :cg-dic (fvmb.new-solver-cg-dic sys phi tol pool-cells)
    :bicgstab-jac (fvmb.new-solver-bicgstab-jac sys phi tol pool-cells)
    :bicgstab-dilu (fvmb.new-solver-bicgstab-dilu sys phi tol pool-cells)
    :gmres-dilu (fvmb.new-solver-gmres-dilu sys phi tol pool-cells restart)
    _ (error (string.format "no solver '%s'" solver-name))))

(fn krylov-iterate! [solver ctx field max-iters ?iter]
  "Run krylov iterations, yielding an inner ctx per step, returning the final step"
  (let [step (solver:iter)
        iter (or ?iter 1)
        record {:instr-name :krylov-iter
                :depth (+ 1 ctx.depth)
                : iter
                : field
                :residual step.residual}]
    (coroutine.yield record)
    (if (or step.done step.breakdown (<= max-iters iter))
        step
        (krylov-iterate! solver ctx field max-iters (+ 1 iter)))))

(fn kryl-exec [rt ctx {: field : opts}]
  (let [sys (chasm.get-sys rt field)
        array (chasm.get-array rt field)
        pool-cells (chasm.get-pool-cells rt field)
        max-iters (or opts.max-iters 1000)
        tol (or opts.tol 1e-06)
        solver-name (or opts.solver :bicgstab-dilu)
        solver (make-solver solver-name sys array pool-cells tol
                            (or opts.restart 20))]
    (coroutine.yield ctx)
    (let [final-step (krylov-iterate! solver ctx field max-iters)]
      {:instr-name :krylov-solve
       :depth ctx.depth
       : field
       :residual final-step.residual
       :norm (array:norm_l2)
       :change (solver:finish_change_into array)
       :breakdown? final-step.breakdown})))

(local krylov-s (make-instr :krylov-s kryl-build kryl-str kryl-exec))

{: laplacian-k : bc-close-s : sys-reset-s : krylov-s}
