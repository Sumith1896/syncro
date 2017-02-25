#lang rosette

(require (only-in "util.rkt" maybe-internal-error))

(provide rhash rhash-has-key? rhash-ref rhash-set)

;; Implementation of hash maps that can handle symbolic keys and values.
;; Requires that keys do not *contain* symbolic values (however they
;; themselves can be symbolic).
;; Pretty stupid implementation. Would not work well if there's a lot
;; of symbolic keys or path conditions.
(define (rhash [assocs '()])
  (define result (hash))
  (let loop ([assocs assocs] [result result])
    (if (null? assocs)
        result
        (loop (cdr assocs)
              (rhash-set result (caar assocs) (cdar assoc))))))

(define (rhash-has-key? rhash key)
  (for*/all ([rhash rhash]
             [key key])
    (begin
      (unless (and (not (term? rhash)) (hash? rhash)
                   (not (term? key)))
        (maybe-internal-error
         (format "Invalid arguments to rhash-has-key?: ~a ~a" rhash key)))
      (hash-has-key? rhash key))))

(define (rhash-ref rhash key)
  (for*/all ([rhash rhash]
             [key key])
    (begin
      (unless (and (not (term? rhash)) (hash? rhash)
                   (not (term? key)))
        (maybe-internal-error
         (format "Invalid arguments to rhash-ref: ~a ~a" rhash key)))
      (hash-ref rhash key))))

(define (rhash-set rhash key value)
  (for*/all ([rhash rhash]
             [key key])
    (begin
      (unless (and (not (term? rhash)) (hash? rhash)
                   (not (term? key)))
        (maybe-internal-error
         (format "Invalid arguments to rhash-ref: ~a ~a" rhash key)))
      (hash-set rhash key value))))