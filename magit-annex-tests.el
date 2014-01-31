;;; magit-annex-tests.el

(require 'ert)
(require 'mocker)
(require 'magit-annex)

;;; Utilities (modified from magit-tests.el)

(defmacro magit-tests--with-temp-dir (&rest body)
  (declare (indent 0) (debug t))
  (let ((dir (gensym)))
    `(let ((,dir (file-name-as-directory (make-temp-file "dir" t))))
       (unwind-protect
           (let ((default-directory ,dir)) ,@body)
         (delete-directory ,dir t)))))

(defmacro magit-tests--with-temp-annex-repo (&rest body)
  (declare (indent 0) (debug t))
  `(magit-tests--with-temp-dir
     (magit-call-git "init" ".")
     (magit-call-git "annex" "init" "test-repo")
     (unwind-protect
         (progn ,@body)
       (call-process "chmod" nil nil nil "-R" "777" "."))))

(defmacro magit-tests--with-temp-bare-repo (&rest body)
  (declare (indent 0) (debug t))
  `(magit-tests--with-temp-dir
     (magit-call-git "init" "--bare" ".")
     ,@body))

(defmacro magit-tests--with-temp-clone (url &rest body)
  (declare (indent 1) (debug t))
  (let ((repo (gensym)))
    `(let ((,repo ,(or url 'default-directory)))
       (magit-tests--with-temp-dir
         (magit-call-git "clone" ,repo ".")
         (magit-call-git "annex" "init" "test-repo")
         ;; Make a normal commit and push.
         (magit-tests--modify-file "file")
         (magit-stage-item "file")
         (magit-call-git "commit" "-m" "normal commit")
         (magit-call-git "push")
         (unwind-protect
             (progn ,@body)
           (call-process "chmod" nil nil nil "-R" "777" "."))))))

(defun magit-tests--modify-file (filename)
  (with-temp-file (expand-file-name filename)
    (insert (symbol-name (gensym "content")))))

(defun magit-tests--should-have-item-title (title section-path)
  (magit-status default-directory)
  (should (member title
                  (mapcar 'magit-section-title
                          (magit-section-children
                           (magit-find-section section-path
                                               magit-root-section))))))

;;; Test magit-annex

;; Annexing

(ert-deftest magit-annex-add-file-to-annex ()
  (magit-tests--with-temp-annex-repo
    (magit-tests--modify-file "file")
    (should (not (file-symlink-p "file")))
    (magit-annex-stage-item "file")
    (should (file-symlink-p "file"))
    (magit-tests--should-have-item-title
     "file" '(staged))))

(ert-deftest magit-annex-add-all-files-to-annex ()
  (magit-tests--with-temp-annex-repo
    (magit-tests--modify-file "file1")
    (magit-tests--modify-file "file2")
    (should (not (file-symlink-p "file1")))
    (let ((magit-annex-stage-all-confirm nil))
      (magit-annex-stage-all))
    (should (file-symlink-p "file1"))
    (should (file-symlink-p "file2"))
    (magit-tests--should-have-item-title
     "file1" '(staged))
    (magit-tests--should-have-item-title
     "file2" '(staged))))

;; Updating

(ert-deftest magit-annex-sync-call ()
  (mocker-let ((magit-annex-run-async (&rest args)
                                      ((:input '("sync") :output t))))
    (magit-annex-sync)))

(ert-deftest magit-annex-merge-call ()
  (mocker-let ((magit-annex-run (&rest args)
                                ((:input '("merge") :output t))))
    (magit-annex-merge)))

(ert-deftest magit-annex-push-git-annex ()
  (magit-tests--with-temp-bare-repo
    (magit-tests--with-temp-clone default-directory
      (magit-tests--modify-file "annex-file")
      (magit-annex-stage-item "annex-file")
      (magit-call-git "commit" "-m" "annex commit")
      (let ((magit-set-upstream-on-push 'dontask))
        (magit-annex-push nil))
      (magit-process-wait)
      ;; Only git annex should have been pushed.
      (should (magit-git-lines "diff" "origin/master")))))

(ert-deftest magit-annex-push-current-and-git-annex ()
  (magit-tests--with-temp-bare-repo
    (magit-tests--with-temp-clone default-directory
      (magit-tests--modify-file "annex-file")
      (magit-annex-stage-item "annex-file")
      (magit-call-git "commit" "-m" "annex commit")
      (let ((magit-set-upstream-on-push 'dontask))
        (magit-annex-push-both nil))
      (magit-process-wait)
      ;; Current branch should also have been pushed, so there should be
      ;; no differences.
      (should (not (magit-git-lines "diff" "origin/master"))))))
