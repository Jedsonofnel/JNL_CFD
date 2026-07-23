;;; (nabla fvm chasm vm) ; CHASM virtual machine implementation

;; deps
(local program (require :nabla.fvm.chasm.program))

;; VM object
(local VM {})
(set VM.__index VM)

(fn new [prog]
  "Create a new VM objec"
  (setmetatable {: prog} VM))

;; Exec object construction

(fn make-exec [block-name depth iter]
  {: block-name
   : depth
   : iter
   :status :running
   :block-end false
   :residuals {}
   :rel-residuals {}
   :iter-counts {}
   :changes {}
   :norms {}
   :breakdowns {}})

(fn make-inner-exec [parent-exec block-name]
  {: block-name
   :depth (+ parent-exec.depth 1)
   :iter 0
   :residuals parent-exec.residuals
   :rel-residuals parent-exec.rel-residuals
   :iter-counts parent-exec.iter-counts
   :changes parent-exec.changes
   :norms parent-exec.norms
   :breakdowns parent-exec.breakdowns})

;; Execution

(fn check-convergence [_pred _exec]
  "Checks predicate tree against exec state and returns true/false"
  ;; TODO implement this
  false)

(fn run-outer-iter! [_?block _?depth] (error "this is a forward declaration"))

(fn run-block! [block exec depth]
  "Run a block's instructions"
  (each [_ inst (ipairs block.instructions)]
    (if inst.instructions
        (run-outer-iter! inst (+ 1 depth))
        ((. block.prog.ISA inst.op :dispatch) block.prog exec inst))
    (coroutine.yield exec)))

(fn run-outer-iter! [block ?depth ?iter]
  (let [iter (or ?iter 1)
        depth (or ?depth 1)
        exec (make-exec block.name depth iter)]
    (run-block! block exec depth)
    (if (or (check-convergence block.convergence exec) (<= block.iters iter))
        exec
        (run-outer-iter! block depth (+ 1 iter)))))

;; VM commands

(fn start! [vm]
  "Start a virtual machine"
  (program.allocate! vm.prog)
  (set vm.co
       (coroutine.create (fn [] (run-outer-iter! vm.prog.main-block 1)
                           (coroutine.yield {:status :done})))))

(fn step! [vm]
  "Run a single VM step (instruction or part of instruction)"
  (if (not vm.co)
      {:status :error :error "VM not started"}
      (let [(ok exec) (coroutine.resume vm.co)]
        (if (not ok)
            {:status :error :error exec}
            exec))))

(fn run-all! [vm]
  "Run all instructions until finished or error"
  (fn loop [result]
    (if (= result.status :running)
        (loop (step! result))
        (if (= result.status :error)
            (error (.. "VM running error: " result.error))
            result)))

  ;; run the loop - love a bit of recursion
  (loop (step! vm)))

;; Method form (for smelly OOP)
(fn VM.start [self]
  "Start VM"
  (start! self))

(fn VM.step [self]
  "Run a single VM step"
  (step! self))

(fn VM.run_all [self]
  "Run until finished or error"
  (run-all! self))

{: new : make-exec : make-inner-exec : start! : step! : run-all!}
