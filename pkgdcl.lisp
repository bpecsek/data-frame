;;; -*- Mode: LISP; Base: 10; Syntax: ANSI-Common-Lisp; Package: CL-USER -*-
;;; Copyright (c) 2020 by Symbolics Pte. Ltd. All rights reserved.

(uiop:define-package #:data-frame.column
  (:use #:cl
        #:alexandria
        #:anaphora
        #:let-plus)
  (:export
   #:column-length
   #:column-summary)
  (:import-from #:clnu
                #:as-alist))

(uiop:define-package #:data-frame
  (:nicknames #:df #:dframe)
  (:use
   #:cl
   #:alexandria
   #:anaphora
   #:let-plus
   #:data-frame.column
   #:cl-slice
   #:cl-slice-dev)
  (:import-from #:clnu #:as-alist)
  (:export
   ;; error messages for ordered keys
   #:duplicate-key
   #:key-not-found
   ;; generic - both data-vector and data-frame
   #:columns
   #:map-columns
   #:column
   #:keys
   #:copy
   #:add-columns
   #:add-column!
   #:add-columns!
   ;; data-vector
   #:data-vector
   #:make-dv
   #:alist-dv
   #:plist-dv
   #:dv
   ;; data-frame
   #:data-frame
   #:make-df
   #:alist-df
   #:plist-df
   #:df
   #:matrix-df
   #:*column-summary-minimum-length*
   ;; transformations for data-frames
   #:map-rows
   #:do-rows
   #:mask-rows
   #:count-rows
   #:map-df
   #:replace-column!
   #:replace-column))
