#|
 This file is a part of deploy
 (c) 2017 Shirakumo http://tymoon.eu (shinmera@tymoon.eu)
 Author: Nicolas Hafner <shinmera@tymoon.eu>
|#

(in-package #:org.shirakumo.deploy)

(defun make-lib-pathname (name)
  (make-pathname :name name :type #+linux "so"
                                  #+darwin "dylib"
                                  #+windows "dll"))

(defun pathname-filename (path)
  (format NIL "~a~@[.~a~]"
          (pathname-name path) (pathname-type path)))

(defun discover-subdirectories (path)
  (labels ((r (path)
             (list* path (mapc #'r (uiop:subdirectories path)))))
    (r path)))

(defun status (level format-string &rest format-args)
  (format T "~& ~a ~?~%" (case level
                           (0 "==>")
                           (1 "  ->")
                           (T "    >"))
          format-string format-args))

(defun env-set-p (envvar)
  (let ((value (uiop:getenv "DEBUG_BOOT")))
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
  (uiop:directory*
   (merge-pathnames (merge-pathnames uiop:*wild-file* uiop:*wild-directory*)
                    path)))

(defun copy-directory-tree (source target &key (copy-root T))
  (labels ((r (path destination)
             (cond ((uiop:directory-pathname-p path)
                    (uiop:copy-file path (make-pathname :name (pathname-name path)
                                                        :type (pathname-type path)
                                                        :defaults destination)))
                   (T
                    (let ((tpath (merge-pathnames (format NIL "~a/" (car (last (pathname-directory path))))
                                                  path)))
                      (ensure-directories-exist tpath)
                      (dolist (subpath (directory-contents path))
                        (r subpath tpath)))))))
    (if copy-root
        (r source target)
        (dolist (subpath (directory-contents source))
          (r subpath target)))))