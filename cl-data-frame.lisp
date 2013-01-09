;;; -*- Mode:Lisp; Syntax:ANSI-Common-Lisp; Coding:utf-8 -*-



(cl:defpackage #:cl-data-frame.column
  (:use #:cl
        #:alexandria
        #:anaphora
        #:let-plus)
  (:export
   #:column-length
   #:column-summary))

(cl:in-package #:cl-data-frame.column)

(defgeneric column-length (column)
  (:documentation "Return the length of column.")
  (:method ((column vector))
    (length column)))

(defstruct bit-vector-summary
  "Summary of a bit vector."
  (length 0 :type array-index :read-only t)
  (count  0 :type array-index :read-only t))

(defstruct numeric-vector-summary
  "Summary of a numeric vector."
  (length 0 :type array-index :read-only t)
  (real-count 0 :type array-index :read-only t)
  (min 0 :type real :read-only t)
  (q25 0 :type real :read-only t)
  (q50 0 :type real :read-only t)
  (q75 0 :type real :read-only t)
  (max 0 :type real :read-only t))

(defun non-numeric-column-summary (column)
  (declare (ignore column))
  "column is not numeric FIXME need to implement")

(defgeneric column-summary (column)
  (:documentation "Return an object that summarizes COLUMN of a DATA-FRAME.  Primarily intended for printing, not analysis, returned values should print nicely.")
  (:method ((column bit-vector))
    (make-bit-vector-summary :length (length column) :count (count 1 column)))
  (:method ((column vector))
    (let+ ((length (length column))
           (elements (loop for elt across column
                           when (realp elt)
                           collect elt)))
      (if (<= (length elements) (/ length 2))
          (non-numeric-column-summary column)
          (let+ ((#(min q25 q50 q75 max)
                   (clnu:quantiles elements #(0 1/4 1/2 3/4 1))))
            (make-numeric-vector-summary :length (length column)
                                         :real-count (length elements)
                                         :min min
                                         :q25 q25
                                         :q50 q50
                                         :q75 q75
                                         :max max))))))


(cl:defpackage #:cl-data-frame
  (:nicknames #:df)
  (:use
   #:cl
   #:alexandria
   #:anaphora
   #:let-plus
   #:cl-data-frame.column
   #:cl-slice
   #:cl-slice-dev)
  (:shadow #:length)
  (:export
   ;; error messages for ordered keys
   #:duplicate-key
   #:key-not-found
   ;; generic - both data-vector and data-frame
   #:columns
   #:keys
   #:copy
   #:as-alist
   #:as-plist
   ;; data-vector
   #:data-vector
   #:make-dv
   #:alist-dv
   #:plist-dv
   #:dv
   ;; data-frame
   #:data-frame
   #:length
   #:make-df
   #:alist-df
   #:plist-df
   #:df
   #:matrix-df
   ;; transformations for both data-vector and data-matrix
   ;; #:add-columns
   ;; #:add-column!
   ;; #:add-columns!
   ;; #:map-rows
   ;; #:select-rows
   ;; #:mapping-rows
   ;; #:selecting-rows
   ;; #:add-map-rows
   ;; #:add-mapping-rows
   ;; #:add-map-rows!
   ;; #:add-mapping-rows!
))

(cl:in-package #:cl-data-frame)

;;; Ordered keys provide a mapping from column keys (symbols) to nonnegative
;;; integers.  They are used internally and the corresponding interface is
;;; NOT EXPORTED.

(defstruct (ordered-keys (:copier nil))
  "Representation of ordered keys.

TABLE maps keys to indexes, starting from zero."
  (table (make-hash-table :test #'eq) :type hash-table :read-only t))

(define-condition duplicate-key (error)
  ((key :initarg :key))
  (:documentation "Duplicate key.")
  (:report (lambda (condition stream)
             (format stream "Duplicate key ~A." (slot-value condition 'key)))))

(define-condition key-not-found (error)
  ((key :initarg :key)
   (keys :initarg :keys))
  (:documentation "Key not found.")
  (:report (lambda (condition stream)
             (format stream "Key ~A not found, valid keys are ~A."
                     (slot-value condition 'key)
                     (slot-value condition 'keys)))))

(defun keys-count (ordered-keys)
  "Number of keys."
  (hash-table-count (ordered-keys-table ordered-keys)))

(defun keys-vector (ordered-keys)
  "Vector of all keys."
  (map 'vector #'car
       (sort (hash-table-alist (ordered-keys-table ordered-keys))
             #'<=
             :key #'cdr)))

(defun key-index (ordered-keys key)
  "Return the index for KEY."
  (let+ (((&values index present?)
          (gethash key (ordered-keys-table ordered-keys))))
    (unless present?
      (error 'key-not-found :key key :keys (keys-vector ordered-keys)))
    index))

(defmethod print-object ((ordered-keys ordered-keys) stream)
  (print-unreadable-object (ordered-keys stream :type t)
    (format stream "~{~a~^, ~}" (keys-vector ordered-keys))))

(defun add-key! (ordered-keys key)
  "Modify ORDERED-KEYS by adding KEY."
  (check-type key symbol)
  (let+ (((&structure ordered-keys- table) ordered-keys)
         ((&values &ign present?) (gethash key table)))
    (when present?
      (error 'duplicate-key :key key))
    (setf (gethash key table) (hash-table-count table)))
  ordered-keys)

(defun ordered-keys (keys)
  "Create an ORDERED-KEYS object from KEYS (a sequence)."
  (aprog1 (make-ordered-keys)
    (map nil (curry #'add-key! it) keys)))

(defun copy-ordered-keys (ordered-keys)
  (let+ (((&structure ordered-keys- table) ordered-keys))
    (make-ordered-keys :table (copy-hash-table table))))

(defun add-keys (ordered-keys &rest keys)
  (aprog1 (copy-ordered-keys ordered-keys)
    (mapc (curry #'add-key! it) keys)))

;;; implementation of SLICE for ORDERED-KEYS

(defmethod axis-dimension ((axis ordered-keys))
  (hash-table-count (ordered-keys-table axis)))

(defmethod canonical-representation ((axis ordered-keys) (slice symbol))
  (key-index axis slice))

(defmethod slice ((ordered-keys ordered-keys) &rest slices)
  (let+ (((slice) slices))
    (ordered-keys
     (slice (keys-vector ordered-keys)
            (canonical-representation ordered-keys slice)))))


;;; generic implementation -- the class is not exported, only the functionality

(defclass data ()
  ((ordered-keys
    :initarg :ordered-keys
    :type ordered-keys)
   (columns
    :initarg :columns
    :type vector
    :reader columns))
  (:documentation "This class is used for implementing both data-vector and data-matrix, and represents and ordered collection of key-column pairs.  Columns are not assumed to have any specific attributes.  This class is not exported."))

(defun make-data (class keys columns)
  "Create a DATA object from KEYS and COLUMNS.  FOR INTERNAL USE.  Always creates a copy of COLUMNS in order to ensure that it is an adjustable array with a fill pointer.  KEYS are converted to ORDERED-KEYS if necessary."
  (let ((n-columns (length columns))
        (ordered-keys (atypecase keys
                        (ordered-keys it)
                        (t (ordered-keys it)))))
    (assert (= n-columns (keys-count ordered-keys)))
    (make-instance class
                   :ordered-keys ordered-keys
                   :columns (make-array n-columns
                                        :adjustable t
                                        :fill-pointer n-columns
                                        :initial-contents columns))))

(defun alist-data (class alist)
  "Create an object of CLASS (subclass of DATA) from ALIST which contains key-column pairs."
  (assert alist () "Can't create an empty data frame.")
  (make-data class (mapcar #'car alist) (mapcar #'cdr alist)))

(defun plist-data (class plist)
  "Create an object of CLASS (subclass of DATA) from PLIST which contains keys and columns, interleaved."
  (alist-data class (plist-alist plist)))

(defun guess-alist? (plist-or-alist)
  "Test if the argument is an ALIST by checking its first element.  Used for deciding which creation function to call."
  (consp (car plist-or-alist)))

(defun keys (data)
  "List of keys."
  (check-type data data)
  (copy-seq (keys-vector (slot-value data 'ordered-keys))))

(defun as-alist (data)
  "Key-column pairs as an alist."
  (check-type data data)
  (map 'list #'cons (keys data) (columns data)))

(defun as-plist (data)
  "Key-column pairs as a plist."
  (check-type data data)
  (alist-plist (as-alist data)))

(defun copy (data &key (key #'identity))
  "Copy data frame or vector.  Keys are copied (and thus can be modified), columns or elements are copyied using KEY, making the default give a shallow copy."
  (let+ (((&slots-r/o ordered-keys columns) data))
    (make-data (class-of data)
               (copy-ordered-keys ordered-keys)
               (map 'vector key columns))))

(defgeneric add-column! (data key column)
  (:documentation  "Modify DATA (a data-frame or data-vector) by adding COLUMN with KEY.  Return DATA.")
  ;; NOTE This is a generic function because data-frames check column length.
  (:method ((data data) (key symbol) column)
    (let+ (((&slots ordered-keys columns) data))
      (add-key! ordered-keys key)
      (vector-push-extend column columns))
    data))

(defun add-columns! (data &rest key-and-column-plist)
  "Modify DATA (a data-frame or data-vector) by adding columns with keys (specified as a plist.  Return DATA."
  (mapc (lambda+ ((key . column))
          (add-column! data key column))
        (plist-alist key-and-column-plist))
  data)

(defun add-columns (data &rest key-and-column-plist)
  "Return a new data-frame or data-vector with keys and columns added.  Does not modify DATA."
  (aprog1 (copy data)
    (apply #'add-columns! it key-and-column-plist)))

(defmacro define-data-subclass (class abbreviation)
  (check-type class symbol)
  (check-type abbreviation symbol)
  (let+ (((&flet fname (prefix)
            (symbolicate prefix '#:- abbreviation)))
         (alist-fn (fname '#:alist))
         (plist-fn (fname '#:plist)))
    `(progn
       (defclass ,class (data)
         ())
       (defun ,(fname '#:make) (keys columns)
         (make-data 'data-vector keys columns))
       (defun ,alist-fn (alist)
         (alist-data ',class alist))
       (defun ,plist-fn (plist)
         (plist-data ',class plist))
       (defun ,abbreviation (&rest plist-or-alist)
         (if (guess-alist? plist-or-alist)
             (,alist-fn plist-or-alist)
             (,plist-fn plist-or-alist))))))

(define-data-subclass data-vector dv)

(defmethod print-object ((data-vector data-vector) stream)
  (print-unreadable-object (data-vector stream :type t)
    (let ((alist (as-alist data-vector)))
      (format stream "~d" (length alist))
      (loop for (key . column) in alist
            do (format stream "~&  ~A  ~A"
                       key column)))))

(define-data-subclass data-frame df)

(defmethod initialize-instance :after ((data-frame data-frame) &rest initargs)
  (declare (ignore initargs))
  (let+ (((first . rest) (coerce (columns data-frame) 'list))
         (length (column-length first)))
    (assert (every (lambda (column)
                     (= length (column-length column)))
                   rest)
            () "Columns don't have the same length.")))

(defun length (data-frame)
  "Length of DATA-FRAME (number of rows)."
  (check-type data-frame data-frame)
  (column-length (aref (columns data-frame) 0)))

(defmethod print-object ((data-frame data-frame) stream)
  (print-unreadable-object (data-frame stream :type t)
    (let ((alist (as-alist data-frame)))
      (format stream "~d x ~d" (length alist) (length data-frame))
      (loop for (key . column) in alist
            do (format stream "~&  ~A  ~A"
                       key (column-summary column))))))

(defun matrix-df (keys matrix)
  "Convert a matrix to a data-frame with the given keys."
  (let+ ((columns (ao:split (ao:transpose matrix) 1)))
    (assert (length= columns keys))
    (alist-df (map 'list #'cons keys columns))))

(defmethod add-column! :before ((data data-frame) key column)
  (assert (= (column-length column) (length data))))

;; 

;; ;;; implementation of SLICE for DATA-FRAME

;; (defmethod slice ((data-frame data-frame) &rest slices)
;;   (let+ (((row-slice &optional (column-slice t)) slices)
;;          ((&slots-r/o ordered-keys columns) data-frame)
;;          (column-slice (canonical-representation ordered-keys column-slice))
;;          (columns (slice columns column-slice))
;;          ((&flet slice-column (column)
;;             (slice column row-slice))))
;;     (if (singleton-representation? column-slice)
;;         (slice-column columns)
;;         (make-data-frame (slice ordered-keys column-slice)
;;                          (map 'vector #'slice-column columns)))))

;; ;;; TODO: (setf slice)

;; 

;; ;;; mapping rows and adding columns

;; (defun map-rows (data-frame keys function &key (element-type t))
;;   "Map rows using FUNCTION, on the columns corresponding to KEYS.  Return the
;; result with the given ELEMENT-TYPE."
;;   (let ((columns (map 'list (curry #'column data-frame) keys))
;;         (length (data-frame-length data-frame)))
;;     (aprog1 (make-array length :element-type element-type)
;;       (dotimes (index length)
;;         (setf (aref it index)
;;               (apply function
;;                      (mapcar (lambda (column)
;;                                (ref column index))
;;                              columns)))))))

;; (defun select-rows (data-frame keys predicate)
;;   "Return a bit-vector containing the result of calling PREDICATE on rows of
;; the columns corresponding to KEYS (0 for NIL, 1 otherwise)."
;;   (map-rows data-frame keys (compose (lambda (flag)
;;                                        (if flag 1 0))
;;                                      predicate)
;;             :element-type 'bit-vector))

;; 

;; ;;; macros

;; (defun process-bindings (bindings)
;;   "Return forms for variables and keys as two values, for use in macros.

;; BINDINGS is a list of (VARIABLE &optional KEY) forms, where VARIABLE is a
;; symbol and KEY is evaluated.  When KEY is not given, it is VARIABLE converted
;; to a keyword.

;; NOT EXPORTED."
;;   (let ((alist (mapcar (lambda+ ((variable
;;                                   &optional (key (make-keyword variable))))
;;                          (check-type variable symbol)
;;                          (cons variable key))
;;                        bindings)))
;;     (values (mapcar #'car alist)
;;             `(list ,@(mapcar #'cdr alist)))))

;; (defun keys-and-lambda-from-bindings (bindings body)
;;   "Process bindings and return a form that can be spliced into the place of
;; KEYS and FUNCTION (using BODY) in functions that map rows.  NOT EXPORTED."
;;   (unless body
;;     (warn "Empty function body."))
;;   (let+ (((&values variables keys) (process-bindings bindings)))
;;     `(,keys (lambda ,variables ,@body))))

;; (defmacro mapping-rows ((data-frame bindings &key (element-type t))
;;                          &body body)
;;   "Map rows of DATA-FRAME and return the resulting column (with the given
;; ELEMENT-TYPE).  See MAP-ROWS.

;; BINDINGS is a list of (VARIABLE KEY) forms, binding the values in each row to
;; the VARIABLEs for the columns designated by KEYs."
;;   `(map-rows ,data-frame
;;              ,@(keys-and-lambda-from-bindings bindings body)
;;              :element-type ,element-type))

;; (defmacro selecting-rows ((data-frame bindings) &body body)
;;   "Map rows using predicate and return the resulting bit vector (see
;; SELECT-ROWS).

;; BINDINGS is a list of (VARIABLE KEY) forms, binding the values in each row to
;; the VARIABLEs for the columns designated by KEYs."
;;   `(select-rows ,data-frame
;;                 ,@(keys-and-lambda-from-bindings bindings body)))

;; (defmacro define-map-add-function-and-macro (blurb (function function-used)
;;                                              macro)
;;   "Macro for defining functions that map and add columns.  BLURB is used in
;; the docstring, FUNCTION is defined using FUNCTION-USED, and MACRO is the
;; corresponding macro."
;;   `(progn
;;      (defun ,function (data-frame keys function result-key
;;                        &key (element-type t))
;;        ,(format nil
;; "Map columns of DATA-FRAME and add the resulting column (with the given
;; ELEMENT-TYPE), designated by RESULT-KEY.  ~A

;; KEYS selects columns, the rows of which are passed on to FUNCTION."
;;                 blurb)
;;        (,function-used data-frame result-key
;;                        (map-rows data-frame keys function
;;                                  :element-type element-type)))
;;      (defmacro ,macro ((data-frame key bindings &key (element-type t))
;;                        &body body)
;;        ,(format nil
;; "Map rows of DATA-FRAME and add the resulting column (with the given
;; ELEMENT-TYPE), designated by KEY.  ~A

;; BINDINGS is a list of (VARIABLE KEY) forms, binding the values in each row to
;; the VARIABLEs for the columns designated by KEYs."
;;                 blurb)
;;        `(,',function ,data-frame
;;                      ,@(keys-and-lambda-from-bindings bindings body)
;;                      ,key
;;                      :element-type ,element-type))))

;; (define-map-add-function-and-macro
;;     "Return a new data-frame."
;;     (add-map-rows add-columns)
;;     add-mapping-rows)

;; (define-map-add-function-and-macro
;;     "Modify (and also return) DATA-FRAME."
;;     (add-map-rows! add-column!)
;;     add-mapping-rows!)

;; 

;; ;;; matrix conversions

;; (defun data-frame-matrix (data-frame)
;;   (ao:combine (data-fr))
;;   (let ((columns )))
;;   )
