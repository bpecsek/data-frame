;;; -*- Mode: LISP; Base: 10; Syntax: ANSI-Common-Lisp; Package: DATA-FRAME-TESTS -*-
;;; Copyright (c) 2020-2022 by Symbolics Pte. Ltd. All rights reserved.

(uiop:define-package #:data-frame-tests
  (:use
   #:cl
   #:alexandria
   #:anaphora
   #:clunit
   #:let-plus
   #:select
   #:data-frame)
  (:import-from #:nu #:as-alist #:as-plist)
  (:export #:run))

(in-package :data-frame-tests)

(defsuite data-frame ())

(defun run (&optional interactive?)
  (run-suite 'data-frame :use-debugger interactive?))

(defsuite data-vector (data-frame))

(deftest data-vector-basics (data-vector)
  (let ((dv (dv :a 1 :b 2 :c 3)))
    (assert-equalp '(:a 1 :b 2 :c 3) (as-plist dv))
    (assert-equalp #(1 2 3) (columns dv))
    (assert-equalp #(:a :b :c) (keys dv))
    (assert-equalp '((:a . 1) (:b . 2) (:c . 3)) (as-alist dv))
    (assert-equalp '(:a 1 :b 2) (as-plist (select dv #(:a :b))))
    (assert-equalp 3 (select dv :c))
    (let ((dv2 (map-columns dv #'1+)))
      (assert-equalp '(:a 2 :b 3 :c 4) (as-plist dv2))
      (assert-true (typep dv2 'data-vector)))))


(defsuite data-frame-basics (data-frame))

(deffixture data-frame-basics (@body)
  (let ((v #(1 2 3 4))
        (b #*0110)
        (s #(a b c d)))
    @body))

(deftest data-frame-creation (data-frame-basics)
  (let* ((plist `(:vector ,v :symbols ,s :bits ,b))
         (df (apply #'df plist))
         (df-plist (plist-df plist))
         (df-alist (alist-df (plist-alist plist))))
    (assert-equalp #(:vector :symbols :bits) (keys df))
    (assert-equalp (vector v s b) (columns df))
    (assert-equalp (vector v s b) (columns df t))
    (assert-equalp (vector v) (columns df #(:vector)))
    (assert-equalp v (columns df :vector))
    (assert-equalp v (columns df -3))
    (assert-equalp `(:vector ,v :symbols ,s :bits ,b) (as-plist df))
    (assert-equalp `((:vector . ,v) (:symbols . ,s) (:bits . ,b)) (as-alist df))
    (assert-equalp (as-alist df) (as-alist df-plist))
    (assert-equalp (as-alist df) (as-alist df-alist))))

(deftest data-frame-select (data-frame-basics)
  (let ((df (df :vector v :symbols s)))
    (assert-equalp `(:vector ,v) (as-plist (select df t #(:vector))))
    (assert-equalp `(:vector ,(select v b)) (as-plist (select df b #(0))))
    (assert-equalp (select v b) (select df b :vector))
    (assert-equalp '(:vector 3 :symbols c) (as-plist (select df 2 t)))
    (assert-equalp `(:vector #(2 4)) (as-plist
                                      (select df
                                             (mask-rows df :vector #'evenp)
                                             #(:vector))))
    (assert-equalp #(2 4) (select df (mask-rows df :vector #'evenp) :vector))))



(defsuite data-frame-operations (data-frame))

(deftest data-frame-map (data-frame-operations)
  (let+ ((df (df :a #(2 3 5)
                 :b #(7 11 13)))
         (product #(14 33 65))
         ((&flet predicate (a b) (<= 30 (* a b))))
         ((&flet predicate-bit (a b) (if (predicate a b) 1 0)))
         (mask #*011))
    (assert-equalp product
        (map-rows df '(:a :b) #'*))
    (assert-equalp `(:p ,product :m ,mask)
        (as-plist (map-df df '(:a :b)
                          (lambda (a b)
                            (vector (* a b) (predicate-bit a b)))
                          '((:p fixnum) (:m bit)))))
    (let ((mask-rows (mask-rows df '(:a :b) #'predicate)))
      (assert-equal mask mask-rows)
      (assert-eq 'bit (array-element-type mask-rows)))
    (assert-equalp (count 1 mask)
        (count-rows df '(:a :b) #'predicate))))

#|
;This test is a bit of a challenge because the operation that determines the symbols for columns compares symbols in the DF package, but here 'a is created in the data-frame-tests package.  Frequent using of filter-rows is enough to convince me that it's working properly, but if someone were to make this test work I'd be grateful.
(deftest filter-rows (data-frame-operations)
  (let+ ((df (df :a #(2 3 5)
                 :b #(7 11 13)))
	 (plst '(:a #(2 3)
		 :b #(7 11))))
    (assert-equal plst (as-plist (filter-rows df (< a 4))))))
|#
(deftest rename! (data-frame-operations)
  (let+ ((df (df :a #(2 3 5)
                 :b #(7 11 13))))
    (assert-equalp #(:a :b) (keys df))
    (rename-column! df :c :a)
    (assert-equalp #(:c :b) (keys df) "Rename failed")))




(defsuite data-frame-add (data-frame))

(deffixture data-frame-add (@body)
  (let* ((plist1 '(:a #(1 2 3)))
         (plist2 '(:b #(4 5 6)))
         (plist12 (append plist1 plist2)))
    @body))

(defmacro test-add (add-function plist1 plist2 append?)
  "Macro for generating the following test:

  1. create a data frame using plist1,

  2. add plist2 using add-function to get a second data frame,

  3. test that the first data frame is uncorrupted if append? is nil, or
     equivalent the concatenated plist otherwise,

  4. test that the second data frame is equivalent to the concatenated plist.

This is a comprehensive test of the add-column family of functions,
destructive or non-destructive."
    (with-unique-names (df df2 plist12)
      (once-only (plist1 plist2)
	`(let* ((,df (plist-df ,plist1))
		(,df2 (apply ,add-function ,df ,plist2))
		(,plist12 (append ,plist1 ,plist2)))
           (assert-equal (if ,append?
                             ,plist12
                             ,plist1)
               (as-plist ,df))
           (assert-equal ,plist12
               (as-plist ,df2))))))

(deftest add-column (data-frame-add)
  (test-add #'add-columns plist1 plist2 nil)
  (test-add #'add-column! plist1 plist2 t)
  (test-add #'add-columns! plist1 plist2 t)
  (assert-equalp '(:a #(1 2 3) :b #(4 5 6)) plist12)) ;this test is only here to quiet the compiler

(deftest add-map (data-frame-add)
  (let* ((plist3 '(:c #(4 10 18)))
         (plist123 (append plist12 plist3)))
    ;; non-destructive
    (let* ((df (plist-df plist12))
           (df2 (add-columns df :c (map-rows df '(:a :b) #'*))))
      (assert-equalp plist12 (as-plist df))
      (assert-equalp plist123 (as-plist df2)))
    ;; destructive, function
    (let* ((df (plist-df plist12))
           (df2 (add-column! df :c (map-rows df '(:a :b) #'*))))
      (assert-equalp plist123 (as-plist df))
      (assert-equalp plist123 (as-plist df2)))))


;;; replace-column

(defsuite replace-column (data-frame))

(deftest replace-column1 (replace-column)
  (let* ((plist '(:a #(1 2 3) :b #(5 7 11)))
         (df (plist-df plist))
         ;; (df-copy (copy df))
         (df1 (replace-column df :a #'1+))
         (df2 (replace-column df :a #(2 3 4)))
         (expected-plist '(:a #(2 3 4) :b #(5 7 11))))
    (assert-equalp expected-plist (as-plist df1))
    (assert-equalp expected-plist (as-plist df2))
    (assert-equalp plist (as-plist df))
    ;; modify destructively
    (replace-column! df :a #'1+)
    (assert-false (equalp plist (as-plist df)))
    (assert-equalp expected-plist (as-plist df))))


(defsuite remove-columns (data-frame))

(deftest remove-columns1 (remove-columns)
  (let* ((plist '(:a #(1 2 3) :b #(5 7 11) :c #(100 200 300)))
         (df (plist-df plist))
         ;; (df-copy (copy df))
         (df1 (remove-columns df '(:a :b)))
         (expected-plist '(:c #(100 200 300))))
    (assert-equalp expected-plist (as-plist df1))
    (assert-equalp plist (as-plist df))

    (remove-column! df :a)
    (assert-false (equalp plist (as-plist df)))
    (assert-equalp '(:b #(5 7 11) :c #(100 200 300)) (as-plist df))))


(defsuite replace-columns (data-frame))
(deftest replace-columns1 (remove-columns)
  (let* ((plist '(:a #(1 2 3) :b #(5 7 11) :c #(100 200 300)))
         (df (plist-df plist)))
    (replace-column! df :a #'1+)
    (assert-false (equalp plist (as-plist df)))
    (assert-equalp '(:a #(2 3 4) :b #(5 7 11) :c #(100 200 300)) (as-plist df))))


(defsuite remove-duplicates (data-frame))

(deftest remove-duplicates1 (remove-duplicates)
  (let* ((dup (make-df '(:a :b :c) '(#(a a 3) #(a a 3) #(a a 333))))
	 (df1 (df-remove-duplicates dup))
	 (expected-plist '(:a #(a 3) :b #(a 3) :c #(a 333))))
    (assert-equalp expected-plist (as-plist df1))))



(defsuite pretty-print (data-frame))

(deftest print-df (pretty-print)
  (let* ((df1 (make-df  '(:a :b :c)
			'(#(a a a)
			  #(b b b)
			  #(3 33 333))))
	 (*print-pretty* t)
	 (expected-string "
;;   A B   C
;; 0 A B   3
;; 1 A B  33
;; 2 A B 333
")
	 (actual-string (make-array '(0) :element-type 'base-char :fill-pointer 0 :adjustable t)))

    (with-output-to-string (s actual-string)
      (print-data df1 s))
    (assert-true (string= expected-string actual-string))))

(deftest print-array (pretty-print)
  (let* ((array1 #2A(#(a a a)
		     #(b b b)
		     #(3 33 333)))
	 (*print-pretty* t)
	 (expected-string ";; 0 A A A
;; 1 B B B
;; 2 3 33 333
")
	 (actual-string (make-array '(0) :element-type 'base-char :fill-pointer 0 :adjustable t)))

    (with-output-to-string (s actual-string)
      (print-array array1 s))
    (assert-true (string= expected-string actual-string))))


(defsuite missing (data-frame))

(deftest d-frame (missing)
  (let ((df (matrix-df #(:a :b :c) #2A((1.7 2.1 :na)
				       (5.4 :na 6.1)
				       (:na 8.3 9.5)))))
    (assert-equalp #2A((nil nil t)
		       (nil t nil)
		       (t nil nil))
      (aops:as-array (missingp df)))))

(deftest array (missing)
  (let ((arr #2A((bar 1 2 3 4 :na 6)
	         (foo 7 8 9 :na 10 11))))
    (assert-equalp #2A((nil nil nil nil nil t nil)
		       (nil nil nil nil t nil nil))
      (missingp arr))))

(deftest vector (missing)
  (let ((vec #(0 1 2 3 4 :na 6)))
    (assert-equalp #(nil nil nil nil nil t nil) (missingp vec))))

(deftest ignore-missing (missing)
  (let ((vec #(0 1 2 3 4 :na 6)))
    (assert-true (nu:num= (funcall (ignore-missing #'mean) vec)
			  2.6666667
			  nu:*num=-tolerance*))))



;;; plist-aops

(defsuite plist-aops (data-frame))

(deftest as-array (plist-aops)
   (let ((arr #2A((1 4) (2 5) (3 6)))
	 (pl '(:a #(1 2 3) :b #(4 5 6))))
     (assert-equalp arr (nth-value 0 (aops:as-array pl)))))

(deftest dims (plist-aops)
   (let ((pl '(:a #(1 2 3) :b #(4 5 6))))
     (assert-equalp '(3 2) (aops:dims pl))
     (assert-equalp 3 (aops:nrow pl))
     (assert-equalp 2 (aops:ncol pl))))


;;; Data frame environment
(defsuite define-data-frame (data-frame))

(deffixture define-data-frame (@body)
  (let* ((v #(1 2 3 4))
         (b #*0110)
         (s #(a b c d)))
    @body))

(deftest define-data-frame (define-data-frame)
  (let* ((plist `(vector ,v symbols ,s bits ,b))
         (df (apply #'df plist)))

    ;; Define an environment
    (df::defdf new-df df)
    (assert-true (boundp 'new-df) "The data frame was not bound")
    (assert-equalp (type-of (symbol-value 'new-df)) 'data-frame "new-df is not bound to a data-frame")

    ;; Ensure variables, package and macros were created
    (assert-true (find-package "NEW-DF") "Data frame package not found")
    (assert-equalp #(1 2 3 4) (eval (find-symbol "VECTOR"  (find-package "NEW-DF"))))
    (assert-equalp #*0110     (eval (find-symbol "BITS"    (find-package "NEW-DF"))))
    (assert-equalp #(a b c d) (eval (find-symbol "SYMBOLS" (find-package "NEW-DF"))))

    ;; ;; Remove symbol and package
    (let ((*package* (find-package "DATA-FRAME-TESTS"))) ;this is normally run from the REPL, and undef assumes (eq *package* REPL package)
      (df::undef data-frame-tests::new-df))

    (assert-false (boundp (find-symbol "NEW-DF" (find-package "DATA-FRAME-TESTS"))) "The data frame was not removed")
    (assert-false (find-package "NEW-DF"))))


