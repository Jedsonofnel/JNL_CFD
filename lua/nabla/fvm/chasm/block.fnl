;; (nabla fvm chasm block) ; programming "blocks" for chasm/fvm

;; deps
(local {: program-get-var} (require :nabla.fvm.chasm.program))

;; Block object
(local Block {})
(set Block.__index Block)

(fn new-block [prog name iters depth]
  "Create a new CHASM block in a given program"
  (assert prog "new-block: prog is nil, required")
  (setmetatable {: prog
                 : name
                 : iters
                 :depth (or depth 1)
                 :instructions []
                 :convergence []} Block))

(fn add-inst! [{: instructions &as block} inst]
  "Add an instruction to the block"
  (table.insert instructions inst)
  block)

(fn get-var [{: prog} v]
  "Get a variable from a block from a var object or string"
  (program-get-var prog v))

;;; Predicates for convergence

(fn until-all! [{: convergence} ...]
  "Add predicate all-node to block convergence containing all passed predicates"
  (let [preds [...]]
    (assert (not= (length preds) 0)
            "block-until-all! expects at least one predicate")
    (table.insert convergence {:kind :all : preds})))

(fn until-any! [{: convergence} ...]
  "Add predicate any-node to block convergence containing passed predicates"
  (let [preds [...]]
    (assert (not= (length preds) 0)
            "block-until-any! expects at least one predicate")
    (table.insert convergence {:kind :any : preds})))

;; TODO: create inner block, until-all, until-any

;;; Instruction emission

(fn Block.emit! [block op-name ...]
  "Add instruction op-name to block, calling op-name.build with rest args"
  (let [isa block.prog.ISA
        entry (or (. isa op-name) (error (.. "unknown ISA op " op-name)))
        inst (entry.build block ...)]
    (set inst.op op-name)
    (add-inst! block inst)))

;;; Pretty printing
;; TODO: consider using this as a way to serialise into valid fennel?
;; requires the API to be stable to be worthwhile though

(fn listing-str [_block _indent-level]
  (error "this is a forward declaration"))

(fn inst-line [prog indent-level inst]
  "Render a single instruction or nested block to a listing line"
  (if inst.instructions
      (.. "\n" (listing-str inst (+ indent-level 1)))
      (let [indent (string.rep "  " indent-level)]
        (string.format "%s%s" indent ((. prog.ISA inst.op) :str inst)))))

(fn listing-str [block indent-level]
  "Instruction listing for a block at a certain indent level"
  (let [indent-level (or indent-level 0)
        indent (string.rep "  " indent-level)
        header (.. indent ">>" block.name)
        body (icollect [_ inst (ipairs block.instructions)]
               (inst-line block.prog indent-level inst))
        footer (.. indent "<<")]
    (table.concat [header (table.concat body "\n") footer] "\n")))

(fn Block.__tostring [{: name : instructions : depth}]
  "Pretty string for a block for display"
  (string.format "<block:%s instrs:%d depth%s>" name (length instructions)
                 depth))

{:new new-block : listing-str : get-var : add-inst!}
