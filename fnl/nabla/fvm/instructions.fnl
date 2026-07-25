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
    (fvmb.laplacian-k! sys mesh gamma)))

(local laplacian-k (make-instr :laplacian-k lapk-build lapk-str lapk-exec))

;;; Boundary conditions

(fn bccs-build [field]
  (let [field (resolve-scalar field)]
    {: field}))

(fn bccs-str [{: field}]
  (simple-instr-str :bc-close-s field))

(local bc-close-tbl
       {:dirichlet-s (fn [sys mesh patch-name {: value}]
                       (fvmb.patch-s-close-d! sys mesh patch-name value))
        :neumann-s (fn [sys mesh patch-name {: grad-n}]
                     (fvmb.patch-s-close-n! sys mesh patch-name grad-n))
        :robin (fn [sys mesh patch-name {: a : b : c}]
                 (fvmb.patch-s-close-r! sys mesh patch-name a b c))})

(fn bccs-exec [rt ctx {: field}]
  "Close BCs for every patch on field's mesh, yielding once per patch"
  (let [{: sys : mesh : bcs} (chasm.get-sys+mesh+bcs rt field)
        field-spec (. bcs field)]
    (each [patch-name _ (pairs (mesh:patches))]
      (let [spec (or (. field-spec patch-name) (. field-spec :__default))
            close-fn (or (. bc-close-tbl spec.kind)
                         (error (.. "no bc close fn for kind: " spec.kind)))]
        (close-fn sys mesh patch-name spec)
        (coroutine.yield ctx)))))

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
    (sys:reset)))

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

(fn krylov-iterate! [solver ctx field max-iters]
  "Run krylov iterations, yielding an inner ctx per step, returning the final step"
  (faccumulate [step {} i 1 max-iters &until (or step.done step.breakdown)]
    (let [step (solver:iter)
          kctx (chasm.make-inner-exec-ctx ctx (.. "krylov:" field))]
      (set kctx.iter i)
      (tset kctx.residuals field step.residual)
      (tset kctx.rel-residuals field step.residual)
      (tset kctx.iter-counts field i)
      (coroutine.yield kctx)
      step)))

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
    (let [final-step (krylov-iterate! solver ctx field max-iters)
          change (solver:finish_change_into array)]
      (tset ctx.changes field change)
      (tset ctx.norms field (array:norm_l2))
      (tset ctx.residuals field (and final-step final-step.residual))
      (when final-step.breakdown (tset ctx.breakdowns field true))
      (coroutine.yield ctx))))

(local krylov-s (make-instr :krylov-s kryl-build kryl-str kryl-exec))

{: laplacian-k : bc-close-s : sys-reset-s : krylov-s}
