#|
 This file is a part of deploy
 (c) 2017 Shirakumo http://tymoon.eu (shinmera@tymoon.eu)
 Author: Nicolas Hafner <shinmera@tymoon.eu>
|#

(in-package #:org.shirakumo.deploy)

(defparameter *data-location* #p"")

(defun data-directory ()
  (merge-pathnames *data-location* (runtime-directory)))

(defun find-relative-path-to (target source)
  (let ((directory (list :relative))
        (temp (make-pathname :directory (copy-list (pathname-directory source))
                             :defaults source)))
    (loop until (loop for a in (rest (pathname-directory target))
                      for b in (rest (pathname-directory temp))
                      always (equal a b))
          do (unless (rest (pathname-directory temp))
               (error "Cannot find a relative path from ~a to ~a." source target))
             (push :up directory)
             (setf temp (make-pathname :directory (butlast (pathname-directory temp))
                                       :defaults temp)))
    (loop for dir in (nthcdr (length (pathname-directory temp))
                             (pathname-directory target))
          do (push dir directory))
    (make-pathname :directory (nreverse directory)
                   :host (pathname-host target)
                   :device (pathname-device target))))

(defun make-lib-pathname (name)
  (make-pathname :name (string name)
                 :type #+linux "so"
                       #+darwin "dylib"
                       #+windows "dll"))

(defun pathname-filename (path)
  (format NIL "~a~@[.~a~]"
          (pathname-name path) (pathname-type path)))

(defun discover-subdirectories (path)
  (labels ((r (path)
             (list* path (mapc #'r (uiop:subdirectories path)))))
    (r (uiop:pathname-directory-pathname path))))

(defun status (level format-string &rest format-args)
  (format T "~& ~a ~?~%" (case level
                           (0 "==>")
                           (1 "  ->")
                           (T "    >"))
          format-string format-args))

(defun env-set-p (envvar)
  (let ((value (uiop:getenv envvar)))
    (when (and value (string/= "" value))
      value)))

(defun redirect-output (target)
  (let ((file (open target
                    :direction :output
                    :if-exists :append
                    :if-does-not-exist :create)))
    (format file "~&>> Deployment log start~%")
    (setf *standard-output* file)
    (setf *error-output* file)
    (setf *trace-output* file)
    (setf *debug-io* (make-echo-stream *debug-io* file))
    file))

(defun runtime-directory ()
  (if (uiop:argv0)
      (uiop:truenamize (uiop:pathname-directory-pathname (uiop:argv0)))
      (uiop:truenamize #p"")))

(defun directory-contents (path)
  (uiop:directory* (merge-pathnames uiop:*wild-file* path)))

(defun copy-directory-tree (source target &key (copy-root T))
  (labels ((r (path destination)
             (cond ((uiop:directory-pathname-p path)
                    (let ((tpath (merge-pathnames (format NIL "~a/" (car (last (pathname-directory path))))
                                                  destination)))
                      (ensure-directories-exist tpath)
                      (dolist (subpath (directory-contents path))
                        (r subpath tpath))))

                   (T
                    (uiop:copy-file path (make-pathname :name (pathname-name path)
                                                        :type (pathname-type path)
                                                        :defaults destination))))))
    (if copy-root
        (r source target)
        (dolist (subpath (directory-contents source))
          (r subpath target)))))

(defun xml-escape (string)
  (with-output-to-string (out)
    (loop for c across string
          do (case c
               (#\< (format out "&lt;"))
               (#\> (format out "&gt;"))
               (#\& (format out "&amp;"))
               (T (write-char c out))))))

(defun system-applicable-p (system-spec)
  (or (eql T system-spec)
      (member system-spec *features*)))

(defun resolve-cffi-spec (spec)
  (labels ((resolve-inner-spec (spec)
             (etypecase spec
               ((or string pathname)
                (list (pathname spec)))
               (cons
                (ecase (first spec)
                  (:or
                   (loop for other in (rest spec)
                         append (resolve-inner-spec other)))
                  (:framework
                   (warn "Deploy does not currently support Darwin frameworks.")
                   ())
                  (:default
                   (list (make-lib-pathname (second spec)))))))))
    (loop for (system-spec spec) in spec
          when (system-applicable-p system-spec)
          append (resolve-inner-spec spec))))

(defun split (split string)
  (let ((out (make-string-output-stream))
        (pieces ()))
    (flet ((add ()
             (let ((string (get-output-stream-string out)))
               (unless (string= string "")
                 (push string pieces)))))
      (loop for c across string
            do (if (char= c split)
                   (add)
                   (write-char c out))
            finally (add))
      (nreverse pieces))))

(defun env-paths (variable)
  (mapcar #'uiop:parse-native-namestring
          (split #+windows #\; #-windows #\: (uiop:getenv variable))))
