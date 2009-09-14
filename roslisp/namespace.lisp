;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Software License Agreement (BSD License)
;; 
;; Copyright (c) 2008, Willow Garage, Inc.
;; All rights reserved.
;;
;; Redistribution and use in source and binary forms, with 
;; or without modification, are permitted provided that the 
;; following conditions are met:
;;
;;  * Redistributions of source code must retain the above 
;;    copyright notice, this list of conditions and the 
;;    following disclaimer.
;;  * Redistributions in binary form must reproduce the 
;;    above copyright notice, this list of conditions and 
;;    the following disclaimer in the documentation and/or 
;;    other materials provided with the distribution.
;;  * Neither the name of Willow Garage, Inc. nor the names 
;;    of its contributors may be used to endorse or promote 
;;    products derived from this software without specific 
;;    prior written permission.
;; 
;; THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND 
;; CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED 
;; WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED 
;; WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A 
;; PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE 
;; COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, 
;; INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR 
;; CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, 
;; PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, 
;; DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER 
;; CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN 
;; CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE 
;; OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS 
;; SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH 
;; DAMAGE.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(in-package roslisp)

(defun fully-qualified-name (name)
  "Do the translation from a client-code-specified name to a fully qualified one.  Handles already-fully-qualified names, tilde for private namespace, unqualified names, and remapped names."
  (declare (string name))
  (case (char name 0)
    (#\/ name)
    (#\~ (concatenate 'string *namespace* *ros-node-name* "/" (subseq name 1)))
    (otherwise
     (concatenate 'string *namespace* (gethash name *remapped-names* name)))))

(defmacro with-fully-qualified-name (n &body body)
  (assert (symbolp n))
  `(let ((,n (fully-qualified-name ,n)))
     ,@body))


(defun process-command-line-remappings (l)
  "Process command line remappings, including the three special cases for remapping the node name, namespace, and setting parameters.  Return alist of params to set."
  (setf *remapped-names* (make-hash-table :test #'equal))
  (let ((params nil))
    (dolist (x l params)
      (dbind (lhs rhs) x
	(cond
	  ((equal lhs "__ns") (setf *namespace* rhs))
	  ((equal lhs "__name") (setf *ros-node-name* rhs))
	  ((equal lhs "__log") (setf *ros-log-location* rhs))
	  ((eql (char lhs 0) #\_) (push (cons (concatenate 'string "~" (subseq lhs 1)) 
					      (let ((rhs-val (read-from-string rhs)))
						(typecase rhs-val
						  (symbol rhs)
						  (otherwise rhs-val)))) params))
	  (t (setf (gethash lhs *remapped-names*) rhs)))))))

(defun postprocess-namespace (ns)
  "Ensure that namespace begins and ends with /"
  (unless (eql (char ns 0) #\/)
    (setf ns (concatenate 'string "/" ns)))
  (unless (eql (char ns (1- (length ns))) #\/)
    (setf ns (concatenate 'string ns "/")))
  ns)

(defun postprocess-node-name (name)
  "Trim any /'s from the node name"
  (string-trim '(#\/) name))

(defun parse-remapping (string)
  "If string is of the form FOO:=BAR, return foo and bar, otherwise return nil."
  (let ((i (search ":=" string)))
    (when i
      (values (subseq string 0 i) (subseq string (+ i 2))))))



(defun handle-command-line-arguments (name)
  "Postcondition: the variables *remapped-names*, *namespace*, and *ros-node-name* are set based on the command line arguments and the environment variable ROS_NAMESPACE as per the ros command line protocol.  Also, arguments of the form _foo:=bar are interpreted by setting private parameter foo equal to bar (currently bar is just read using the lisp reader; it should eventually use yaml conventions)"
  (let ((remappings
	 (mapcan #'(lambda (s) (mvbind (lhs rhs) (parse-remapping s) (when lhs (list (list lhs rhs))))) 
		 (rest sb-ext:*posix-argv*))))
    (setf *namespace* (or (sb-ext:posix-getenv "ROS_NAMESPACE") "/")
	  *ros-node-name* name)
    (let ((params (process-command-line-remappings remappings)))
      (setf *namespace* (postprocess-namespace *namespace*)
	    *ros-node-name* (postprocess-node-name *ros-node-name*))

      (ros-debug (roslisp top) "Command line arguments are ~a" (rest sb-ext:*posix-argv*))
      (ros-info (roslisp top) "Node name is ~a" *ros-node-name*)
      (ros-info (roslisp top) "Namespace is ~a" *namespace*)
      (ros-info (roslisp top) "Params are ~a" params)
      (ros-info (roslisp top) "Remappings are:")
      (maphash #'(lambda (k v) (ros-info (roslisp top) "  ~a = ~a" k v)) *remapped-names*)
      params)))


