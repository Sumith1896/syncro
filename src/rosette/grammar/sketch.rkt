#lang rosette

(require "language.rkt"
         "../types.rkt" "../variable.rkt" "../util.rkt"
         racket/serialize)

(provide make-lifted force-type deserialize-lifted-grammar)

(define deserialize-lifted-grammar
  (make-deserialize-info
   (lambda (val) (lifted-grammar val (and val (infer-type val)) #f))
   (const #f)))
(struct lifted-grammar lifted-writer ([value #:mutable] [type #:mutable]) #:transparent
  #:property prop:serializable
  (make-serialize-info
   (lambda (s) (vector (lifted-grammar-value s)))
   #'deserialize-lifted-grammar
   #f
   (or (current-load-relative-directory) (current-directory)))
  #:methods gen:lifted
  [(define/generic gen-eval-lifted eval-lifted)
   (define/generic gen-lifted-code lifted-code)
   (define/generic gen-fold-lifted fold-lifted)
   (define (eval-lifted self)
     (check-grammar-defined self)
     (gen-eval-lifted (lifted-grammar-value self)))

   (define (lifted-code self)
     (check-grammar-defined self)
     (gen-lifted-code (lifted-grammar-value self)))

   ;; TODO: This is quite a weird abstraction to provide. Do something better.
   (define (fold-lifted self mapper reducer)
     (if (lifted-grammar-value self)
         (gen-fold-lifted (lifted-grammar-value self) mapper reducer)
         (mapper self)))]

  #:methods gen:inferable
  [(define/generic gen-infer-type infer-type)
   (define/generic gen-mutable? mutable?)

   (define (infer-type self)
     (check-grammar-defined self)
     (gen-infer-type (lifted-grammar-value self)))

   (define (force-type-helper self type mapping)
     (if (lifted-grammar-type self)
         (unless (unify-types type (lifted-grammar-type self))
           (error "Impossible"))
         (set-lifted-grammar-type! self type)))

   (define (mutable? self)
     (check-grammar-defined self)
     (gen-mutable? (lifted-grammar-value self)))])

(define (check-grammar-defined x)
  (unless (lifted-grammar-value x)
    (internal-error "Lifted grammar has not performed grammar generation yet!")))
(define (make-lifted-grammar [type #f])
  (lifted-grammar #f type))


;; Sets the types of any lifted-grammar nodes in lifted such that the
;; overall program has the desired type.
;; Errors if it is impossible to do this.
;; (-> lifted? type? void/c)
(define (force-type lifted type grammar-fn)
  (define mapping (make-type-map))

  ;; Generate and collect constraints on type variables in the mapping.
  ;; Also sets lifted-grammar-types to the necessary types, though
  ;; these types may contain type variables.
  (define result (force-type-helper lifted type mapping))

  ;; Concretize the type and generate the program for lifted-grammars
  (define (handle-node node)
    (when (lifted-grammar? node)
      (let* ([orig-type (lifted-grammar-type node)]
             [new-type (replace-type-vars orig-type mapping #t)])
        (set-lifted-grammar-type! node new-type)
        (set-lifted-grammar-value! node (grammar-fn new-type)))))

  ;; Call handle-node on all lifted-grammars
  (fold-lifted lifted handle-node (const #t)))

;; Given an S-expression for normal Racket code, converts it into code in
;; the lifted language. Has support for the ?? form.
;; Note: The documentation suggests that map does process its arguments in
;; order, so I rely on it here. This is important for define.
;; TODO: Need to handle mutability
(define (make-lifted terminal-info operators code)
  (define id->operator
    (for/hash ([op operators] #:when (lifted-variable? op))
      (values (variable-symbol op) op)))

  (define recurse (curry make-lifted terminal-info operators))
  
  (match code
    ;; Special forms
    [`(begin . ,args) (apply begin^ (map recurse args))]
    [`(if ,x ,y ,z) (apply if^ (map recurse (list x y z)))]
    [`(set! ,var ,val) (apply set!^ (map recurse (list var val)))]
    [`(error . ,args) (lifted-error)]

    ;; Define is tricky, since we need to figure out the type of the
    ;; new variable. We require that the user gives us an rhs does
    ;; not contain any calls to the grammar.
    ;; Same thing with loops.
    [`(define ,var ,val)
     (let* ([value (recurse val)]
            [type (infer-type value)])
       (send terminal-info make-and-add-terminal var type)
       (define^ (recurse var) value))]
    [`(for-enum-set ((,var ,set-expr)) . ,body)
     (let* ([set (recurse set-expr)]
            [set-type (infer-type set)])
       (unless (Set-type? set-type)
         (internal-error
          (format "make-lifted -- Not a set type ~a" set-type)))

       (send terminal-info make-and-add-terminal var
             (Set-content-type set-type))
       (for-enum-set^ (recurse var) set (recurse `(begin ,@body))))]

    ;; Grammar generation
    [`(??) (make-lifted-grammar)]
    [`(?? ,type) (make-lifted-grammar type)]

    ;; Procedure application
    [`(,proc . ,args) (apply (recurse proc) (map recurse args))]

    ;; Base cases
    [(? number?) code]
    [(? symbol?)
     (cond [(send terminal-info has-terminal? code)
            (send terminal-info get-terminal-by-id code)]
           [(hash-has-key? id->operator code)
            (hash-ref id->operator code)]
           [else
            (error (format "Unknown symbol ~a -- MAKE-LIFTED" code))])]))
