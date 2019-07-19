;;; ivy-fuz.el --- Integrate Ivy and Fuz -*- lexical-binding: t -*-

;; Copyright (C) 2019 Zhu Zihao

;; Author: Zhu Zihao <all_but_last@163.com>
;; URL:
;; Version: 0.0.1
;; Package-Requires: ((emacs "25.1") (ivy "20190717"))
;; Keywords: lisp

;; This file is NOT part of GNU Emacs.

;; This file is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; For a full copy of the GNU General Public License
;; see <https://www.gnu.org/licenses/>.

;;; Commentary:

;;

;;; Code:

(require 'inline)
(require 'ivy)
(require 'fuz)
(require 'fuz-extra)

(eval-when-compile
  (require 'pcase))

;;; Customize

(defgroup ivy-fuz ()
  "Sort `ivy' candidates by fuz"
  :group 'ivy
  :prefix "ivy-fuz-")

(defcustom ivy-fuz-sorting-method 'skim
  "The fuzzy sorting method in use.

The value should be `skim' or `clangd', skim's scoring function is a little
slower but return better result than clangd's."
  :type '(choice
          (const :tag "Skim" skim)
          (const :tag "Clangd" clangd))
  :group 'ivy-fuz)

(defcustom ivy-fuz-sort-limit 5000
  ""
  :type '(choice
          (const :tag "Unlimited" nil)
          integer)
  :group 'ivy-fuz)

(defvar ivy-fuz--sort-timer (float-time))
(defvar ivy-fuz--score-cache (make-hash-table :test #'equal))

;;; Utils

(define-inline ivy-fuz--fuzzy-score (pattern str)
  "Calc the fuzzy match score of STR with PATTERN.

Sign: (-> Str Str Long)"
  (inline-quote
   (or (pcase-exhaustive ivy-fuz-sorting-method
         (`clangd (fuz-calc-score-clangd ,pattern ,str))
         (`skim (fuz-calc-score-skim ,pattern ,str)))
       most-negative-fixnum)))

(define-inline ivy-fuz--fuzzy-indices (pattern str)
  "Return all char positions where STR fuzzy matched with PATTERN.

Sign: (-> Str Str (Option (Listof Long)))"
  (inline-quote
   (pcase-exhaustive ivy-fuz-sorting-method
     (`clangd (fuz-find-indices-clangd ,pattern ,str))
     (`skim (fuz-find-indices-skim ,pattern ,str)))))

(defun ivy-fuz--get-score-data (pattern cand)
  "Return (LENGTH SCORE) by matching CAND with PATTERN.

Sign: (-> Str Str (List Long Long))"
  (let ((len (length cand)))
    ;; FIXME: Short pattern may have higher score matching longer pattern
    ;; than exactly matching itself
    ;; e.g. "ielm" will prefer [iel]m-[m]enu than [ielm]
    (if (string= cand pattern)
        (list len most-positive-fixnum)
      (list len (ivy-fuz--fuzzy-score pattern cand)))))

;;;###autoload
(defalias 'ivy-fuz-fuzzy-regex #'ivy--regex-fuzzy)

;;;###autoload
(defun ivy-fuz-sort-fn (pattern cands)
  (condition-case nil
      (let* ((bolp (string-prefix-p "^" pattern))
             (fuzzy-regex
              (concat "\\`"
                      (and bolp (regexp-quote (substring pattern 1 2)))
                      (mapconcat
                       (lambda (x)
                         (setq x (char-to-string x))
                         (concat "[^" x "]*" (regexp-quote x)))
                       (if bolp (substring pattern 2) pattern)
                       "")))
             (realpat (if bolp (substring pattern 1) pattern))
             (memo-fn (fuz-memo-function
                       (lambda (cand) (ivy-fuz--get-score-data realpat cand))
                       #'equal)))
        (let ((counter 0)
              cands-to-sort)
          (while (and cands
                      (< counter ivy-fuz-sort-limit))
            (when (string-match-p fuzzy-regex (car cands))
              (push (pop cands) cands-to-sort)
              (cl-incf counter)))

          (setq cands (fuz-sort-with-key! cands #'< #'length))
          (nconc (fuz-sort-with-key! cands-to-sort
                                     (pcase-lambda (`(,len1 ,scr1) `(,len2 ,scr2))
                                         (if (= scr1 scr2)
                                             (< len1 len2)
                                           (> scr1 scr2)))
                                     memo-fn)
                 cands)))
    (error cands)))

;;;###autoload
(defun ivy-fuz-highlight-fn (str)
  ""
  (fuz-highlighter (ivy-fuz--fuzzy-indices (ivy--remove-prefix "^" ivy-text)
                                           str)
                   (ivy--minibuffer-face 0)
                   str))

(provide 'ivy-fuz)

;; Local Variables:
;; coding: utf-8
;; End:

;; ivy-fuz.el ends here.
