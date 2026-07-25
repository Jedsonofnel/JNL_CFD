;;; (nabla ui) ; ui shim (will be removed come web paradigm)

(local opt (require :nabla.core.optional))
(local internal (opt.require :nabla.ui_internal))

;; Some internal state (AHHH)
(var default-ui nil)

(fn handle-closed? [handle]
  (if (not handle) true
      (handle:closed)))

(fn clear-default-if! [handle]
  (when (and handle (= handle default-ui))
    (set default-ui nil)))

(fn fresh-default! []
  (set default-ui (internal.spawn))
  default-ui)

(fn default! []
  (if (or (not default-ui) (default-ui:closed))
      (fresh-default!)
      default-ui))

(fn try-display [handle send]
  (if (or (handle-closed? handle) (not (handle:focus)))
      false
      (send handle)))

(fn display-with-recovery! [?handle send]
  (let [h (or ?handle (default!))]
    (if (try-display h send) true
        (?handle) false
        (do
          (clear-default-if! h)
          (try-display (fresh-default!) send)))))

(fn spawn! []
  (let [h (internal.spawn)]
    (when (or (not default-ui) (handle-closed? default-ui))
      (set default-ui h))
    h))

(fn display-mesh [mesh ?handle]
  (display-with-recovery! ?handle #($1:send_mesh mesh)))

(fn set-field! [name data ?handle]
  (let [h (or ?handle default-ui)]
    (if (or (not h) (h:closed)) false
        (h:set_field name data))))

(fn set-vector! [name fx fy ?handle]
  (let [h (or ?handle default-ui)]
    (if (or (not h) (h:closed)) false
        (h:set_vector name fx fy))))

(fn view-field [name ?handle]
  (let [h (or ?handle default-ui)]
    (if (or (not h) (h:closed)) false
        (h:view_field name))))

(fn view-mesh [show? ?handle]
  (let [h (or ?handle default-ui)]
    (if (or (not h) (h:closed)) false
        (h:view_mesh show?))))

(fn close! [?handle]
  (let [h (or ?handle default-ui)]
    (when h (h:close) (clear-default-if! h))))

{: default!
 : spawn!
 : display-mesh
 : set-field!
 : set-vector!
 : view-field
 : view-mesh
 : close!}
