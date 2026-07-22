;;; (nabla fvm chasm isa) ; instruction set

;;; Deps
(local fvmb (require :nabla.fvm.bindings))
(local {: number?} (require :nabla.util))
(local vm (require :nabla.fvm.chasm.vm))

;;; Helpers

(fn assert-same-domain [op-name ...]
  "Assert that all vars passed live on the same domain"
  (let [fields [...]
        domain (. fields 1 :domain-name)
        same? (accumulate [same? true _ field (ipairs fields) &until (not same?)]
                (= field.domain-name domain))]
    (when (not same?)
      (error (string.format "%s input vars need to belong to the same domain"
                            op-name)))))

(fn get-const [op-name k default]
  "Resolve a constant k from either a number or named constant object"
  (case k
    {: value} value
    (where num (number? num)) num
    nil (or default 1)
    _ (error (string.format "%s: expects a constant" op-name))))

(fn get-scalar [prog op-name v]
  "Resolve a var from a block and assert it is a scalar ()"
  (let [v (prog:get-var v)]
    (when (not= v.rank 0)
      (error (string.format "%s: '%s' must be a scalar" op-name v.name)))
    v))

(fn get-scalars [prog op-name ...]
  "Resolve multiple vars, asserting all are scalar"
  (let [resolved (icollect [_ v (ipairs [...])]
                   (get-scalar prog op-name v))]
    resolved))

(fn get-prog [program op-name field]
  "Resolve a var and assert it is a prognostic scalar"
  (let [v (get-scalar program op-name field)]
    (when (not v.has-sys?)
      (error (string.format "%s: '%s' must be prognostic (have a linalg system)"
                            op-name v.name)))
    v))

;;;; Raw instructions

;;; Field operators

;; Face normal cellwise
(local face-norm-cw {})

(fn face-norm-cw.build [block w xc yc]
  "Build cellwise face normal instruction"
  (let [[w xc yc] (get-scalars block :face-norm-cw w xc yc)]
    (assert-same-domain :face-norm-cw w xc yc)
    {: w : xc : yc}))

(fn face-norm-cw.str [{: w : xc : yc}]
  "Pretty string for face-normal-cw instruction"
  (string.format "face normal cw %s %s %s" w xc yc))

(fn face-norm-cw.dispatch [prog _exec {: w : xc : yc}]
  "Execute face-normal-cw"
  (let [[w xc yc] (get-scalars prog :face-norm-cw w xc yc)
        {: mesh : pools} (. prog.domains w.domain-name)]
    (fvmb.face-norm-cw mesh w.array xc.array yc.array pools.face)))

;;; Implicit FVM operators

;; Laplacian

(local laplacian-k {})

(fn laplacian-k.build [block phi gamma-k]
  "Apply laplacian to phi system with constant gamma"
  (let [field (get-scalar block :laplacian-k phi)
        gamma (get-const :laplacian-k gamma-k)]
    {: field : gamma}))

(fn laplacian-k.str [{: field : gamma}]
  "Pretty string for laplacian-k instruction"
  (string.format "laplacian constant-gamma %s %g" field.name gamma))

(fn laplacian-k.dispatch [prog _exec {: field : gamma}]
  "Execute laplacian-k instruction"
  (let [field (get-scalar prog :laplacian-k field)
        gamma (get-const :laplacian-k gamma)
        {: mesh} (. prog.domains field.domain-name)]
    (fvmb.laplacian-k field.fvsys mesh gamma)))

;; Div TODO

;;; Boundary conditions

(local bc-close-s {})

(fn bc-close-s.build [block field]
  "Apply BCs for scalar field to system (ie close the system)"
  (let [field (get-prog block :bc-close-s field)]
    {: field}))

(fn bc-close-s.str [{: field}]
  "Pretty string for bc-close-s instruction"
  (string.format "close BCs scalar %s" field.name))

(local bc-close-tbl {})

(fn bc-close-tbl.dirichlet-s [sys mesh patch-name {: value}]
  (fvmb.patch-s-close-d sys mesh patch-name value))

(fn bc-close-tbl.neumann-s [sys mesh patch-name {: grad-n}]
  (fvmb.patch-s-close-n sys mesh patch-name grad-n))

(fn bc-close-tbl.robin-s [sys mesh patch-name {: a : b : c}]
  (fvmb.patch-s-close-r sys mesh patch-name a b c))

(fn bc-close-s.dispatch [prog exec {: field}]
  "Execute bc-close-s instruction"
  (let [field (get-prog prog :bc-close-s field)
        {: mesh : bcs} (. prog.domains field.domain-name)
        field-spec (. bcs field.name)]
    (each [_ patch (ipairs (mesh:patches))]
      (let [spec (or (. field-spec patch.name) field-spec.__default)
            close-fn (or (. bc-close-tbl spec.kind)
                         (error (.. "could not find bc close fn for kind: "
                                    spec.kind)))]
        (close-fn field.fvsys mesh patch.name spec)
        (coroutine.yield exec)))))

;;; Linear algebra

(local sys-reset-s {})

(fn sys-reset-s.build [block field]
  "Reset linear algebra system for scalar field"
  (let [field (get-prog block :sys-reset-s field)]
    {: field}))

(fn sys-reset-s.str [{: field}]
  "Pretty string for sys-reset-s instruction"
  (string.format "system reset %s" field.name))

(fn sys-reset-s.dispatch [prog _exec {: field}]
  "Execute sys-reset-s"
  (let [{: fvsys} (get-prog prog :sys-reset-s field)]
    (fvsys:reset)))

(local krylov-s {})

(fn krylov-s.build [block field ?opts]
  "Perform a krylov iterative solve on the field's system"
  (let [field (get-prog block.prog :krylov-s field)
        opts (or ?opts {})]
    {: field : opts}))

(fn krylov-s.str [{: field : opts}]
  "Pretty string for krylov instruction"
  (string.format "krylov solve for %s TODO OPTS" field.name))

(fn make-solver [solver-name sys field pool-cw opts]
  "Make a solver for the given solver name"
  (let [tol (or opts 1e-06)
        restart (or opts.restart 20)]
    (case (solver-name:lower)
      :cg-jac
      (fvmb.new-solver-cg-jac sys field tol pool-cw)
      :cg-dic
      (fvmb.new-solver-cg-dic sys field tol pool-cw)
      :bicgstab-jac
      (fvmb.new-solver-bicgstab-jac sys field tol pool-cw)
      :bicgstab-dilu
      (fvmb.new-solver-bicgstab-dilu sys field tol pool-cw)
      :gmres-dilu
      (fvmb.new-solver-gmres-dilu sys field tol pool-cw restart)
      _ ; TODO the error could print the available options perhaps
      (error (string.format "Could not make solver '%s', not an available option"
                            solver-name)))))

(fn krylov-iterate! [solver exec field max-iters]
  "Run krylov iterations, yielding progress each step, returning final step"
  (faccumulate [step {} i 1 max-iters &until (or step.done step.breakdown)]
    (let [step (solver:iter)
          kexec (vm.make-inner-exec exec (.. "krylov:" field.name))]
      (set kexec.iter i)
      (tset kexec.residuals field.name step.residual)
      (tset kexec.rel-residuals field.name step.residual)
      (tset kexec.iter-counts field.name i)
      (coroutine.yield kexec)
      step)))

(fn krylov-finish! [solver exec field final-step]
  "Write solver results back into field array and exec bookkeeping"
  (let [change (solver:finish_change_into field.array)]
    (tset exec.changes field.name change)
    (tset exec.norms field.name (field.array:norm_l2))
    (tset exec.residuals field.name (and final-step final-step.residual))
    (when final-step.breakdown
      (tset exec.breakdowns field.name true))))

(fn krylov-s.dispatch [prog exec {: field : opts}]
  "Execute krylov-s instruction"
  (let [field (get-prog prog :krylov-s field)
        domain (. prog.domains field.domain-name)
        max-iters (or opts.max-iters 1000)
        solver-name (or opts.solver :bicgstab-dilu)
        solver (make-solver solver-name field.fvsys domain.pool-cell opts)]
    (coroutine.yield exec)
    (let [final-step (krylov-iterate! solver exec field max-iters)]
      (krylov-finish! solver exec field final-step)
      (coroutine.yield exec))))

;;;; Polymorphic instructions TODO

;; sys-reset laplacian face-normal krylov

;;; Public exports

{: face-norm-cw : laplacian-k : bc-close-s : sys-reset-s}
