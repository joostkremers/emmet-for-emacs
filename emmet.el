;;; emmet.el --- Unofficial Emmet support for Emacs  -*- lexical-binding: t -*-

;; Copyright (C) 2021-     Joost Kremers      (@joostkremers https://github.com/joostkremers)
;; Copyright (C) 2014-     Dmitry Mukhutdinov (@flyingleafe  https://github.com/flyingleafe)
;; Copyright (C) 2014-     William David Mayo (@pbocks       https://github.com/pobocks)
;; Copyright (C) 2013-     Shin Aoyama        (@smihica      https://github.com/smihica)
;; Copyright (C) 2009-2012 Chris Done

;; Author: Shin Aoyama <smihica@gmail.com>
;; Maintainer: Joost Kremers <joostkremers@fastmail.fm>
;; URL: https://github.com/joostkremers/emmet-for-emacs
;; Version: 2.0
;; Keywords: convenience
;; Package-Requires: ((emacs "26.1"))

;; This file is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.
;;
;; This file is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;;; Commentary:
;;
;; Unfold CSS-selector-like expressions to markup.  Intended to be used
;; with sgml-like languages; xml, html, xhtml, xsl, etc.
;;
;; See the function `emmet' and <https://emmet.io/> for more information.
;;
;; To install, Copy emmet.el to your load-path and add to your .emacs:
;;
;;    (require 'emmet)
;;
;; Example setup:
;;
;;    (add-to-list 'load-path "~/path/to/emmet/")
;;    (require 'emmet)
;;    (add-hook 'sgml-mode-hook 'emmet-mode) ;; Auto-start on any markup modes
;;    (add-hook 'html-mode-hook 'emmet-mode)
;;    (add-hook 'css-mode-hook  'emmet-mode)
;;
;; Enable the minor mode with M-x emmet-mode.
;;
;; See ``Test cases'' section for a complete set of expression types.
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;;; History:
;;
;; This is a fork of `emmet-mode' <https://github.com/smihica/emmet-mode>, which
;; is itself a fork of `zencoding-mode' <https://github.com/rooney/zencoding> to
;; support Emmet's feature.


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;;; Code:

(defconst emmet--version "2.0")

(require 'cl-lib)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Generic parsing macros and utilities

(defmacro emmet-aif (test-form then-form &rest else-forms)
  "Anaphoric if. Temporary variable `it' is the result of test-form."
  `(let ((it ,test-form))
     (if it ,then-form ,@(or else-forms '(it)))))

(defmacro emmet-pif (test-form then-form &rest else-forms)
  "Parser anaphoric if. Temporary variable `it' is the result of test-form."
  `(let ((it ,test-form))
     (if (not (eq 'error (car it))) ,then-form ,@(or else-forms '(it)))))

(defmacro emmet-parse (regex nums label &rest body)
  "Parse according to a regex and update the `input' variable."
  `(emmet-aif (emmet-regex ,regex input ',(number-sequence 0 nums))
                  (let ((input (elt it ,nums)))
                    ,@body)
                  `,`(error ,(concat "expected " ,label))))

(defmacro emmet-run (parser then-form &rest else-forms)
  "Run a parser and update the input properly, extract the parsed
   expression."
  `(emmet-pif (,parser input)
                  (let ((input (cdr it))
                        (expr (car it)))
                    ,then-form)
                  ,@(or else-forms '(it))))

(defmacro emmet-por (parser1 parser2 then-form &rest else-forms)
  "OR two parsers. Try one parser, if it fails try the next."
  `(emmet-pif (,parser1 input)
                  (let ((input (cdr it))
                        (expr (car it)))
                    ,then-form)
                  (emmet-pif (,parser2 input)
                                 (let ((input (cdr it))
                                       (expr (car it)))
                                   ,then-form)
                                 ,@else-forms)))

(defmacro emmet-find (direction regexp &optional limit-of-search repeat-count)
  "Regexp-search in given direction, returning the position (or nil)
and leaving the point in place."
  `(save-excursion
     (if (,(intern (concat "re-search-" direction))
          ,regexp ,limit-of-search t ,repeat-count)
         (match-beginning 0))))

(defun emmet-regex (regexp string refs)
  "Return a list of (`ref') matches for a `regex' on a `string' or nil."
  (if (string-match (concat "^" regexp "\\([^\n]*\\)$") string)
      (mapcar (lambda (ref) (match-string ref string))
              (if (sequencep refs) refs (list refs)))
    nil))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Emmet minor mode

(defgroup emmet nil
  "Customization group for emmet-mode."
  :group 'convenience)

(defun emmet-expr-on-line ()
  "Extract a emmet expression and the corresponding bounds
   for the current line."
  (let* ((end (point))
         (start (emmet-find-left-bound))
         (line (buffer-substring-no-properties start end))
         (expr (emmet-regex "\\([ \t]*\\)\\([^\n]+\\)" line 2)))
    (if (cl-first expr)
        (list (cl-first expr) start end))))

(defun emmet-find-left-bound ()
  "Find the left bound of an emmet expr"
  (save-excursion (save-match-data
    (let ((char (char-before))
          (in-style-attr (looking-back "style=[\"'][^\"']*" nil))
          (syn-tab (make-syntax-table)))
      (modify-syntax-entry ?\\ "\\")
      (while char
        (cond ((and in-style-attr (member char '(?\" ?\')))
               (setq char nil))
              ((member char '(?\} ?\] ?\)))
               (with-syntax-table syn-tab
                 (backward-sexp) (setq char (char-before))))
              ((eq char ?\>)
               (if (looking-back "<[^>]+>" (line-beginning-position))
                   (setq char nil)
                 (progn (backward-char) (setq char (char-before)))))
              ((not (string-match-p "[[:space:]\n;]" (string char)))
               (backward-char) (setq char (char-before)))
              (t
               (setq char nil))))
      (point)))))

(defcustom emmet-indentation 4
  "Number of spaces used for indentation."
  :type '(number :tag "Spaces")
  :group 'emmet)

(defcustom emmet-indent-after-insert t
  "Indent region after insert?"
  :type 'boolean
  :group 'emmet)

(defcustom emmet-use-style-tag-and-attr-detection t
  "When true, enables detection of style tags and attributes in HTML
to provide proper CSS abbreviations completion."
  :type 'boolean
  :group 'emmet)

(defcustom emmet-self-closing-tag-style "/"
  "Self-closing tags style.

This determines how Emmet expands self-closing tags.

E.g., FOO is a self-closing tag.  When expanding \"FOO\":

When \" /\", the expansion is \"<FOO />\".
When \"/\", the expansion is \"<FOO/>\".
When \"\", the expansion is \"<FOO>\".

Default value is \"/\".

NOTE: only \" /\", \"/\" and \"\" are valid."
  :type '(choice (const :tag " />" " /")
                 (const :tag "/>" "/")
                 (const :tag ">" ""))
  :group 'emmet)

(defvar emmet-use-css-transform nil
  "When true, transform Emmet snippets into CSS, instead of the usual HTML.")
(make-variable-buffer-local 'emmet-use-css-transform)

(defvar emmet-use-sass-syntax nil
  "When true, uses Sass syntax for CSS abbreviations expanding,
e. g. without semicolons")
(make-variable-buffer-local 'emmet-use-sass-syntax)


(defvar emmet-css-major-modes
  '(css-mode
    scss-mode
    sass-mode
    less-mode
    less-css-mode)
  "Major modes that use emmet for CSS, rather than HTML.")

(defvar emmet-fallback-filter '("html")
  "Fallback filter for `emmet-default-filter', if none is found.")

(defvar emmet-file-filter nil
  "File local filter used by `emmet-default-filter'.")
(make-variable-buffer-local 'emmet-file-filter)

(defun emmet-transform (input)
  (if (or (emmet-detect-style-tag-and-attr) emmet-use-css-transform)
      (emmet-css-transform input)
    (emmet-html-transform input)))

(defun emmet-detect-style-tag-and-attr ()
  (let* ((style-attr-end "[^=][\"']")
         (style-attr-begin "style=[\"']")
         (style-tag-end "</style>")
         (style-tag-begin "<style>"))
    (and emmet-use-style-tag-and-attr-detection
         (or
          (emmet-check-if-between style-attr-begin style-attr-end) ; style attr
          (emmet-check-if-between style-tag-begin style-tag-end))))) ; style tag

(defun emmet-check-if-between (begin end)
  (let ((begin-back (emmet-find "backward" begin))
        (end-back (emmet-find "backward" end))
        (begin-front (emmet-find "forward" begin))
        (end-front (emmet-find "forward" end)))
    (and begin-back end-front
         (or (not end-back) (> begin-back end-back))
         (or (not begin-front) (< end-front begin-front)))))

(defcustom emmet-preview-default nil
  "If non-nil then preview is the default action.
This determines how `emmet-expand-line' works by default."
  :type 'boolean
  :group 'emmet)

;;;###autoload
(defun emmet-expand-line (arg)
  "Replace the current line's emmet expression with the corresponding expansion.
If prefix ARG is given or region is visible call `emmet-preview' to start an
interactive preview.

Otherwise expand line directly.

For more information see `emmet-mode'."
  (interactive "P")
  (let* ((here (point))
         (preview (if emmet-preview-default (not arg) arg))
         (beg (if preview
                  (emmet-find-left-bound)
                (when (use-region-p) (region-beginning))))
         (end (if preview
                  here
                (when (use-region-p) (region-end)))))
    (if (and preview beg)
        (progn
          (goto-char here)
          (emmet-preview beg end))
      (let ((expr (emmet-expr-on-line)))
        (if expr
            (let ((markup (emmet-transform (cl-first expr))))
              (when markup
                (delete-region (cl-second expr) (cl-third expr))
                (emmet-insert-and-flash markup)
                (emmet-reposition-cursor expr))))))))

(defvar emmet-mode-keymap
  (let
      ((map (make-sparse-keymap)))
    (define-key map (kbd "C-j") 'emmet-expand-line)
    (define-key map (kbd "<C-return>") 'emmet-expand-line)
    (define-key map (kbd "<C-M-right>") 'emmet-next-edit-point)
    (define-key map (kbd "<C-M-left>") 'emmet-prev-edit-point)
    (define-key map (kbd "C-c C-c w") 'emmet-wrap-with-markup)
    map)
  "Keymap for emmet minor mode.")

(defun emmet-after-hook ()
  "Initialize Emmet's buffer-local variables."
  (if (memq major-mode emmet-css-major-modes)
      (setq emmet-use-css-transform t))
  (if (eq major-mode 'sass-mode)
      (setq emmet-use-sass-syntax t)))

;;;###autoload
(define-minor-mode emmet-mode
  "Minor mode for writing HTML and CSS markup.
With emmet for HTML and CSS you can write a line like

  ul#name>li.item*2

and have it expanded to

  <ul id=\"name\">
    <li class=\"item\"></li>
    <li class=\"item\"></li>
  </ul>

This minor mode defines keys for quick access:

\\{emmet-mode-keymap}

Home page URL `http://www.emacswiki.org/emacs/Emmet'.

See also `emmet-expand-line'."
  :lighter (" Emmet" (:eval (if emmet-preview-mode "[P]" "")))
  :keymap emmet-mode-keymap
  :after-hook (emmet-after-hook))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Emmet yasnippet integration

(defun emmet-transform-yas (input)
  (let* ((leaf-count 0)
         (emmet-leaf-function
          (lambda ()
            (format "$%d" (cl-incf leaf-count)))))
    (emmet-transform input)))

;;;###autoload
(defun emmet-expand-yas ()
  (interactive)
  (let ((expr (emmet-expr-on-line)))
    (if expr
        (let* ((markup (emmet-transform-yas (cl-first expr)))
               (filled (replace-regexp-in-string "><" ">\n<" markup)))
          (delete-region (cl-second expr) (cl-third expr))
          (insert filled)
          (indent-region (cl-second expr) (point))
          (if (fboundp 'yas/expand-snippet)
              (yas/expand-snippet
               (buffer-substring (cl-second expr) (point))
               (cl-second expr) (point)))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Real-time preview
;;

;;;;;;;;;;
;; Lennart's version

(defvar emmet-preview-input nil)
(make-local-variable 'emmet-preview-input)
(defvar emmet-preview-output nil)
(make-local-variable 'emmet-preview-output)
(defvar emmet-old-show-paren nil)
(make-local-variable 'emmet-old-show-paren)

(defface emmet-preview-input
  '((default :box t :inherit secondary-selection))
  "Face for preview input field."
  :group 'emmet)

(defface emmet-preview-output
  '((default :inherit highlight))
  "Face for preview output field."
  :group 'emmet)

(defvar emmet-preview-keymap
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "RET") 'emmet-preview-accept)
    (define-key map (kbd "<return>") 'emmet-preview-accept)
    (define-key map [(control ?g)] 'emmet-preview-abort)
    map))

(defun emmet-html-text-p (markup)
  (string-match "^[\s|\t|\n|\r]*<.*$" markup))

(defun emmet-preview-accept ()
  (interactive)
  (let ((ovli emmet-preview-input)
        (expr (emmet-expr-on-line)))
    (if (not (and (overlayp ovli)
                  (bufferp (overlay-buffer ovli))))
        (message "Preview is not active")
      (let* ((indent (current-indentation))
             (markup (emmet-preview-transformed indent)))
        (when markup
          (delete-region (overlay-start ovli) (overlay-end ovli))
          (emmet-insert-and-flash markup)
          (emmet-reposition-cursor expr)))))
  (emmet-preview-abort))

(defun emmet-html-next-insert-point (str)
  (with-temp-buffer
    (insert str)
    (goto-char (point-min))
    (or
     (emmet-aif (emmet-go-to-edit-point 1 t) (- it 1)) ; try to find an edit point
     (emmet-aif (re-search-forward ".+</" nil t) (- it 3))   ; try to place cursor after tag contents
     (length str))))                             ; ok, just go to the end

(defun emmet-css-next-insert-point (str)
  (let ((regexp (if emmet-use-sass-syntax ": *\\($\\)" ": *\\(;\\)$")))
    (save-match-data
      (set-match-data nil t)
      (string-match regexp str)
      (or (match-beginning 1) (length str)))))

(defvar emmet-flash-ovl nil)
(make-variable-buffer-local 'emmet-flash-ovl)

(defun emmet-remove-flash-ovl (buf)
  (with-current-buffer buf
    (when (overlayp emmet-flash-ovl)
      (delete-overlay emmet-flash-ovl))
    (setq emmet-flash-ovl nil)))

(defcustom emmet-insert-flash-time 0.5
  "Time to flash insertion.
Set this to a negative number if you do not want flashing the
expansion after insertion."
  :type '(number :tag "Seconds")
  :group 'emmet)

(defcustom emmet-move-cursor-after-expanding t
  "If non-nil the the cursor position is
moved to before the first closing tag when the exp was expanded."
  :type 'boolean
  :group 'emmet)

(defcustom emmet-move-cursor-between-quotes nil
  "If emmet-move-cursor-after-expands is non-nil and this is non-nil then
cursor position will be moved to after the first quote."
  :type 'boolean
  :group 'emmet)

(defun emmet-reposition-cursor (expr)
  (let ((output-markup (buffer-substring-no-properties (cl-second expr) (point))))
    (when emmet-move-cursor-after-expanding
      (let ((p (point))
            (new-pos (if (emmet-html-text-p output-markup)
                         (emmet-html-next-insert-point output-markup)
                       (emmet-css-next-insert-point output-markup))))
        (goto-char
         (+ (- p (length output-markup))
            new-pos))))))

(defun emmet-insert-and-flash (markup)
  (emmet-remove-flash-ovl (current-buffer))
  (let ((here (point)))
    (insert markup)
    (when emmet-indent-after-insert
      (indent-region here (point))
      (setq here
            (save-excursion
              (goto-char here)
              (skip-chars-forward "[:space:]")
              (point))))
    (setq emmet-flash-ovl (make-overlay here (point)))
    (overlay-put emmet-flash-ovl 'face 'emmet-preview-output)
    (when (< 0 emmet-insert-flash-time)
      (run-with-idle-timer emmet-insert-flash-time
                           nil 'emmet-remove-flash-ovl (current-buffer)))))

;;;###autoload
(defun emmet-preview (beg end)
  "Expand emmet between BEG and END interactively.
This will show a preview of the expanded emmet code and you can
accept it or skip it."
  (interactive (if (use-region-p)
                   (list (region-beginning) (region-end))
                 (list nil nil)))
  (emmet-preview-abort)
  (if (not beg)
      (message "Region not active")
    (setq emmet-old-show-paren show-paren-mode)
    (show-paren-mode -1)
    (let ((here (point)))
      (goto-char beg)
      (forward-line 1)
      (unless (= 0 (current-column))
        (insert "\n"))
      (let* ((opos (point))
             (ovli (make-overlay beg end nil nil t))
             (ovlo (make-overlay opos opos))
             (info (propertize " Emmet preview. Choose with RET. Cancel by stepping out. \n"
                               'face 'tooltip)))
        (overlay-put ovli 'face 'emmet-preview-input)
        (overlay-put ovli 'keymap emmet-preview-keymap)
        (overlay-put ovlo 'face 'emmet-preview-output)
        (overlay-put ovlo 'before-string info)
        (setq emmet-preview-input  ovli)
        (setq emmet-preview-output ovlo)
        (add-hook 'before-change-functions 'emmet-preview-before-change t t)
        (goto-char here)
        (add-hook 'post-command-hook 'emmet-preview-post-command t t)))))

(defun emmet-preview-online ()
  "Display `emmet-preview' on the fly as the user types.

To use this, add the function as a local hook:

  (add-hook 'post-self-insert-hook 'emmet-preview-online t t)

or enable `emmet-preview-mode'."
  (ignore-errors
    (let* ((expr (emmet-expr-on-line))
           (text (nth 0 expr))
           (beg (nth 1 expr))
           (end (nth 2 expr)))
      (let ((wap (word-at-point)))
        (when (and (not (equal wap text))
                   (emmet-transform text))
          (emmet-preview beg end))))))

(define-minor-mode emmet-preview-mode
  "When enabled, automatically show `emmet-preview' as the user types.

See `emmet-preview-online'."
  :init-value nil
  :group 'emmet
  (if emmet-preview-mode
      (add-hook 'post-self-insert-hook 'emmet-preview-online :append :local)
    (remove-hook 'post-self-insert-hook 'emmet-preview-online :local)))

(defvar emmet-preview-pending-abort nil)
(make-variable-buffer-local 'emmet-preview-pending-abort)

(defun emmet-preview-before-change (beg end)
  (when
      (or (> beg (overlay-end emmet-preview-input))
          (< beg (overlay-start emmet-preview-input))
          (> end (overlay-end emmet-preview-input))
          (< end (overlay-start emmet-preview-input)))
    (setq emmet-preview-pending-abort t)))

(defun emmet-preview-abort ()
  "Abort emmet code preview."
  (interactive)
  (setq emmet-preview-pending-abort nil)
  (remove-hook 'before-change-functions 'emmet-preview-before-change t)
  (when (overlayp emmet-preview-input)
    (delete-overlay emmet-preview-input))
  (setq emmet-preview-input nil)
  (when (overlayp emmet-preview-output)
    (delete-overlay emmet-preview-output))
  (setq emmet-preview-output nil)
  (remove-hook 'post-command-hook 'emmet-preview-post-command t)
  (when emmet-old-show-paren (show-paren-mode 1)))

(defun emmet-preview-post-command ()
  (condition-case err
      (emmet-preview-post-command-1)
    (error (message "emmet-preview-post: %s" err))))

(defun emmet-preview-post-command-1 ()
  (if (and (not emmet-preview-pending-abort)
           (<= (point) (overlay-end emmet-preview-input))
           (>= (point) (overlay-start emmet-preview-input)))
      (emmet-update-preview (current-indentation))
    (emmet-preview-abort)))

(defun emmet-preview-transformed (indent)
  (let* ((string (buffer-substring-no-properties
		  (overlay-start emmet-preview-input)
		  (overlay-end emmet-preview-input))))
    (let ((output (emmet-transform string)))
      (when output
        output))))

(defun emmet-update-preview (indent)
  (let* ((pretty (emmet-preview-transformed indent))
         (show (when pretty
                 (propertize pretty 'face 'highlight))))
    (when show
      (overlay-put emmet-preview-output 'after-string
                   (concat show "\n")))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Implementation of "Go to Edit Point" functionality ;;
;; http://docs.emmet.io/actions/go-to-edit-point/     ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun emmet-go-to-edit-point (count &optional only-before-closed-tag)
  (let*
      ((between-tags
        (if only-before-closed-tag "\\(><\\)/" "\\(><\\)"))
       (indented-line "\\(^[[:blank:]]+$\\)")
       (between-quotes
        (if emmet-move-cursor-between-quotes "\\(=\\(\"\\|'\\)\\{2\\}\\)" nil))
       (whole-regex
        (mapconcat 'identity
                   (delq nil
                         (list between-tags indented-line between-quotes))
                   "\\|"))
       (edit-point (format "\\(%s\\)" whole-regex)))
    (if (> count 0)
	(progn
	  (forward-char)
	  (let
	      ((search-result (re-search-forward edit-point nil t count)))
	    (if search-result
		(progn
		  (cond
		   ((match-string 2) (goto-char (- (match-end 2) 1)))
		   ((match-string 3) (end-of-line))
                   ((match-string 4) (backward-char)))
		  (point))
		(backward-char))))
      (progn
	(backward-char)
	(let
	    ((search-result (re-search-backward edit-point nil t (- count))))
	  (if search-result
	      (progn
		(cond
		 ((match-string 2) (goto-char (- (match-end 2) 1)))
		 ((match-string 3) (end-of-line))
		 ((match-string 4) (forward-char 2)))
		(point))
	      (forward-char)))))))

(defcustom emmet-postwrap-goto-edit-point nil
  "Goto first edit point after wrapping markup?"
  :type 'boolean
  :group 'emmet)

;;;###autoload
(defun emmet-wrap-with-markup (wrap-with)
  "Wrap region with markup."
  (interactive "sExpression to wrap with: ")
  (let* ((multi (string-match "\\*$" wrap-with))
         (txt (buffer-substring-no-properties (region-beginning) (region-end)))
         (to-wrap (if multi
                      (split-string txt "\n")
                    (list txt)))
         (initial-elements (replace-regexp-in-string
                            "\\(.*\\(\\+\\|>\\)\\)?[^>*]+\\*?[[:digit:]]*$"
                            "\\1" wrap-with t))
         (terminal-element (replace-regexp-in-string
                            "\\(.*>\\)?\\([^>*]+\\)\\(\\*[[:digit:]]+$\\)?\\*?$"
                            "\\2" wrap-with t))
         (multiplier-expr (replace-regexp-in-string
                           "\\(.*>\\)?\\([^>*]+\\)\\(\\*[[:digit:]]+$\\)?\\*?$"
                           "\\3" wrap-with t))
         (expr (concat
                initial-elements
                (mapconcat (lambda (el)
                             (concat terminal-element
                                     "{!!!"
                                     (secure-hash 'sha1 el)
                                     "!!!}"
                                     multiplier-expr))
                           to-wrap
                           "+")))
         (markup
          (cl-reduce
           (lambda (result text)
             (replace-regexp-in-string
              (concat "!!!" (secure-hash 'sha1 text) "!!!")
              text
              result t t))
           to-wrap
           :initial-value (emmet-transform expr))))
    (when markup
      (delete-region (region-beginning) (region-end))
      (insert markup)
      (indent-region (region-beginning) (region-end))
      (if emmet-postwrap-goto-edit-point
          (let ((end (region-end)))
            (goto-char (region-beginning))
            (unless (ignore-errors (progn (emmet-next-edit-point 1) t))
              (goto-char end)))
        ))))

;;;###autoload
(defun emmet-next-edit-point (count)
  (interactive "^p")
  (unless (or emmet-use-css-transform (emmet-go-to-edit-point count))
    (error "Last edit point reached.")))

;;;###autoload
(defun emmet-prev-edit-point (count)
  (interactive "^p")
  (unless (or emmet-use-css-transform (emmet-go-to-edit-point (- count)))
    (error "First edit point reached.")))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Default configuration

(defun emmet-read-json (path)
  "Read the JSON file PATH.
The contents of PATH is returned as a hash table.  JSON `null' is
converted to nil."
  (condition-case err
      (if (fboundp 'json-parse-buffer)
          (with-temp-buffer
            (insert-file-contents path)
            (goto-char (point-min))
            (json-parse-buffer :false-object nil))
        ;; Fall back on `json.el'.
        (require 'json)
        (let ((json-object-type 'hash-table)
              (json-false nil))
          (json-read-file path)))
    (json-parse-error
     (message "[Emmet] Invalid JSON in `%s'" (file-name-nondirectory path)))
    (error (signal (car err) (cdr err)))))

(defconst emmet-default-conf-dir
  (file-name-as-directory
   (expand-file-name "conf"
                     (file-name-directory (or load-file-name buffer-file-name))))
  "Default configuration directory.
This is the default directory for `preferences.json' and `snippets.json'.")

(defvar emmet-snippets (emmet-read-json (expand-file-name "snippets.json" emmet-default-conf-dir))
  "Hash table containing `conf/snippets.json'.")

(defvar emmet-preferences (emmet-read-json (expand-file-name "preferences.json" emmet-default-conf-dir))
  "Hash table containing `conf/preferences.json'.")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; XML abbrev

(defvar
  emmet-tag-aliases-table
  (gethash "aliases" (gethash "html" emmet-snippets)))

(defun emmet-expr (input)
  "Parse a zen coding expression with optional filters."
  (emmet-pif (emmet-parse "\\(.*?\\)|" 2 "expr|filter" it)
                 (let ((input (elt it 1))
                       (filters (elt it 2)))
                   (emmet-pif (emmet-extract-filters filters)
                                  (emmet-filter input it)
                                  it))
                 (emmet-filter input (emmet-default-filter))))

(defun emmet-subexpr (input)
  "Parse a zen coding expression with no filter. This pretty much defines precedence."
  (emmet-run emmet-siblings
                 it
                 (emmet-run emmet-parent-child
                                it
                                (emmet-run emmet-multiplier
                                               it
                                               (emmet-run emmet-pexpr
                                                              it
                                                              (emmet-run emmet-text
                                                                             it
                                                                             (emmet-run emmet-tag
                                                                                            it
                                                                                            '(error "no match, expecting ( or a-zA-Z0-9"))))))))

(defun emmet-extract-filters (input)
  "Extract filters from expression."
  (emmet-pif (emmet-parse "\\([^\\|]+?\\)|" 2 "" it)
                 (let ((filter-name (elt it 1))
                       (more-filters (elt it 2)))
                   (emmet-pif (emmet-extract-filters more-filters)
                                  (cons filter-name it)
                                  it))
                 (emmet-parse "\\([^\\|]+\\)" 1 "filter name" `(,(elt it 1)))))

(defun emmet-filter (input filters)
  "Construct AST with specified filters."
  (emmet-pif (emmet-subexpr input)
                 (let ((result (car it))
                       (rest (cdr it)))
                   `((filter ,filters ,result) . ,rest))
                 it))

(defun emmet-default-filter ()
  "Default filter(s) to be used if none is specified."
  (or emmet-file-filter
      (let* ((file-ext (car (emmet-regex ".*\\(\\..*\\)" (or (buffer-file-name) "") 1)))
             (defaults '(".html" ("html")
                         ".htm"  ("html")
                         ".haml" ("haml")
                         ".clj"  ("hic")
                         ".cljs" ("hic")))
             (default-else emmet-fallback-filter)
             (selected-default (member file-ext defaults)))
        (if selected-default
            (cadr selected-default)
          default-else))))

(defun emmet-numbering (input)
  (emmet-parse
   "\\(\\$+\\)" 2 "numbering, $"
   (let ((doller (elt it 1)))
     (emmet-pif (emmet-parse
                 "@\\([0-9-][0-9]*\\)" 2 "numbering args"
                 (let* ((args (read (elt it 1)))
                        (direction  (not (or (eq '- args) (cl-minusp args))))
                        (base       (if (eq '- args) 1 (abs args))))
                   `((n ,(length doller) ,direction ,base) . ,input)))
                it
                `((n ,(length doller) t 1) . ,input)))))

(defun emmet-split-numbering-expressions (input)
  (cl-labels
      ((iter (input)
             (emmet-aif (emmet-regex "\\([^$]*\\)\\(\\$.*\\)" input '(1 2))
                (let ((prefix (car it))
                      (input (cadr it)))
                  (if (and (< 0 (length prefix)) ; check if ..\\$... or ...$...
                           (string-equal (substring prefix -1) "\\"))
                      `(,(store-substring prefix (- (length prefix) 1) ?$)
                        ,@(iter (substring input 1)))
                    (let ((res (emmet-numbering input)))
                      `(,prefix ,(car res) ,@(iter (cdr res))))))
                (list input))))
    (let ((res (iter input)))
      (if (cl-every #'stringp res)
          (apply #'concat res)
        `(numberings ,@res)))))

(defun emmet-instantiate-numbering-expression (i lim exp)
  (cl-labels ((instantiate
               (i lim exps)
               (apply #'concat
                      (mapcar
                       (lambda (exp)
                         (if (listp exp)
                             (let ((digits (cl-second exp))
                                   (direction (cl-third exp))
                                   (base (cl-fourth exp)))
                               (let ((num (if direction (+ base i)
                                            (- (+ lim (- base 1)) i))))
                                 (format (concat "%0" (format "%d" digits) "d") num)))
                           exp)) exps)))
              (search
               (i lim exp)
               (if (listp exp)
                   (if (eql (car exp) 'numberings)
                       (instantiate i lim (cdr exp))
                     ;; Should do like this for real searching.
                     ;; But stack overflow occurs.
                     ;; (cons (search-numberings i lim (car exp))
                     ;;       (search-numberings i lim (cdr exp)))
                     (mapcar (lambda (exp) (search i lim exp)) exp))
                 exp)))
    (search i lim exp)))

(defun emmet-multiply-expression (multiplicand exp)
  (cl-loop for i to (- multiplicand 1) collect
           (emmet-instantiate-numbering-expression i multiplicand exp)))

(defun emmet-multiplier (input)
  (emmet-pif (emmet-run emmet-pexpr
                        it
                        (emmet-run emmet-tag
                                   it
                                   (emmet-run emmet-text
                                              it
                                              '(error "expected *n multiplier"))))
             (let* ((expr (car it)) (input (cdr it))
                    (multiplier expr))
               (emmet-parse "\\*\\([0-9]+\\)" 2 "*n where n is a number"
                            (let ((multiplicand (read (elt it 1))))
                              `((list ,(emmet-multiply-expression
                                        multiplicand
                                        multiplier))
                                . ,input))))))

(defun emmet-tag (input)
  "Parse a tag."
  (emmet-run
   emmet-tagname
   (let ((tagname (cadr expr))
         (has-body? (cddr expr)))
     (emmet-pif
      (emmet-run emmet-identifier
                 (emmet-tag-classes
                  `(tag (,tagname ,has-body? ,(cddr expr))) input)
                 (emmet-tag-classes
                  `(tag (,tagname ,has-body? nil)) input))
      (let ((tag-data (cadar it)) (input (cdr it)))
        (emmet-pif (emmet-run
                    emmet-properties
                    (let ((props (cdr expr)))
                      `((tag ,(append tag-data (list props))) . ,input))
                    `((tag ,(append tag-data '(nil))) . ,input))
                   (let ((expr (car it)) (input (cdr it)))
                     (cl-destructuring-bind (expr . input)
                         (emmet-tag-text expr input)
                       (or
                        (emmet-expand-lorem expr input)
                        (emmet-expand-tag-alias expr input))))))))
   (emmet-default-tag input)))

(defun emmet-get-first-tag (expr)
  (if (listp expr)
      (if (listp (car expr))
          (emmet-get-first-tag (car expr))
        (if (eql (car expr) 'tag)
            expr
          (emmet-get-first-tag (cdr expr))))
    nil))

(defun emmet-lorem (input)
  (emmet-aif
   (and (stringp input) (emmet-regex "\\(?:lorem\\|ipsum\\)\\([0-9]*\\)" input '(0 1)))
   (let ((w (elt it 1)))
     (let ((word-num (if (string-equal w "") 30 (read w))))
       word-num))))

(defun emmet-expand-lorem (tag input)
  (let ((tag-data (cadr tag)))
    (let ((tag-name (car tag-data)))
      (emmet-aif (emmet-lorem tag-name)
                 (if (cl-equalp (cdr tag-data) '(t nil nil nil nil))
                     `((text (lorem ,it)) . ,input)
                   `((tag ("div" ,@(cl-subseq tag-data 1 -1) (lorem ,it))) . ,input))))))

(defun emmet-expand-tag-alias (tag input)
  (let ((tag-data (cadr tag)))
    (let ((tag-name (car tag-data)))
      (emmet-aif
       (gethash tag-name emmet-tag-aliases-table)
       (let ((expr (if (stringp it)
                       (emmet-subexpr it)
                     it)))
         (prog1
             (let ((rt (copy-tree expr)))
               (let ((first-tag-data (cadr (emmet-get-first-tag rt))))
                 (setf (cl-second first-tag-data) (cl-second tag-data))
                 (setf (cl-third first-tag-data)  (cl-third tag-data))
                 (setf (cl-fourth first-tag-data)
                       (cl-remove-duplicates
                        (append (cl-fourth first-tag-data)
                                (cl-fourth tag-data)) :test #'string=))
                 (setf (cl-fifth first-tag-data)
                       (cl-remove-duplicates
                        (append (cl-fifth first-tag-data)
                                (cl-fifth tag-data))
                        :test #'(lambda (p1 p2)
                                  (eql (car p1) (car p2)))))
                 (setf (cl-sixth first-tag-data) (cl-sixth tag-data))
                 (setf (cdr rt) (concat (cdr rt) input))
                 rt))
           (puthash tag-name expr emmet-tag-aliases-table)))
       `(,tag . ,input)))))

(defun emmet-default-tag (input)
  "Parse a #id or .class"
  (emmet-parse "\\([#|\\.]\\)" 1 "tagname"
                   (emmet-tag (concat "div" (elt it 0)))))

(defun emmet-tag-text (tag input)
  (let ((tag-data (cadr tag)))
    (emmet-run emmet-text
                   (let ((txt (cadr expr)))
                     `((tag ,(append tag-data (list txt))) . ,input))
                   `((tag ,(append tag-data '(nil))) . ,input))))

(defun emmet-tag-props (tag input)
  (let ((tag-data (cadr tag)))
    (emmet-run emmet-properties
                   (let ((props (cdr expr)))
                     `((tag ,(append tag-data (list props))) . ,input))
                   `((tag ,(append tag-data '(nil))) . ,input))))

(defun emmet-props (input)
  "Parse many props."
    (emmet-run emmet-prop
                   (emmet-pif (emmet-props input)
                                  `((props . ,(cons expr (cdar it))) . ,(cdr it))
                                  `((props . ,(list expr)) . ,input))))

(defun emmet-prop (input)
  (emmet-parse
   " *" 1 "space"
   (emmet-run
    emmet-name
    (let ((name (cdr expr)))
      (emmet-pif (emmet-prop-value name input)
                     it
                     `((,(read name) "") . ,input))))))

(defun emmet-prop-value (name input)
  (emmet-pif (emmet-parse "=\"\\(.*?\\)\"" 2
                          "=\"property value\""
                          (let ((value (elt it 1))
                                (input (elt it 2)))
                            `((,(read name) ,(emmet-split-numbering-expressions value)) . ,input)))
             it
             (emmet-parse "=\\([^\\,\\+\\>\\{\\}\\ )]*\\)" 2
                          "=property value"
                          (let ((value (elt it 1))
                                (input (elt it 2)))
                            `((,(read name) ,(emmet-split-numbering-expressions value)) . ,input)))))

(defun emmet-tag-classes (tag input)
  (let ((tag-data (cadr tag)))
    (emmet-run emmet-classes
                   (let ((classes (mapcar (lambda (cls) (cdadr cls))
                                          (cdr expr))))
                     `((tag ,(append tag-data (list classes))) . ,input))
                   `((tag ,(append tag-data '(nil))) . ,input))))

(defun emmet-tagname (input)
  "Parse a tagname a-zA-Z0-9 tagname (e.g. html/head/xsl:if/br)."
  (emmet-parse "\\([a-zA-Z!][a-zA-Z0-9:!$@-]*\/?\\)" 2 "tagname, a-zA-Z0-9"
                   (let* ((tag-spec (elt it 1))
                          (empty-tag (emmet-regex "\\([^\/]*\\)\/" tag-spec 1))
                          (tag (emmet-split-numbering-expressions
                                (if empty-tag (car empty-tag) tag-spec))))
                     `((tagname . (,tag . ,(not empty-tag))) . ,input))))

(defun emmet-text (input)
  "A zen coding expression innertext."
  (emmet-parse "{\\(\\(?:\\\\.\\|[^\\\\}]\\)*?\\)}" 2 "inner text"
               (let ((txt (emmet-split-numbering-expressions (elt it 1))))
                 (if (listp txt)
                     (setq txt (cons (car txt) (cons (replace-regexp-in-string "\\\\\\(.\\)" "\\1" (cadr txt)) (cddr txt))))
                   (setq txt (replace-regexp-in-string "\\\\\\(.\\)" "\\1" txt)))
                 `((text ,txt) . ,input))))

(defun emmet-properties (input)
  "A bracketed emmet property expression."
  (emmet-parse "\\[\\(.*?\\)\\]" 2 "properties"
                `(,(car (emmet-props (elt it 1))) . ,input)))


(defun emmet-pexpr (input)
  "A zen coding expression with parentheses around it."
  (emmet-parse "(" 1 "("
                   (emmet-run emmet-subexpr
                                  (emmet-aif (emmet-regex ")" input '(0 1))
                                                 `(,expr . ,(elt it 1))
                                                 '(error "expecting `)'")))))

(defun emmet-parent-child (input)
  "Parse an tag>e expression, where `n' is an tag and `e' is any
   expression."
  (cl-labels
      ((listing (parents child input)
                (let ((len (length parents)))
                  `((list ,(cl-map 'list
                                   (lambda (parent i)
                                     `(parent-child ,parent
                                                    ,(emmet-instantiate-numbering-expression i len child)))
                                   parents
                                   (cl-loop for i to (- len 1) collect i))) . ,input))))
    (emmet-run
     emmet-multiplier
     (let* ((items (cadr expr))
            (rest (emmet-child-sans expr input)))
       (if (not (eq (car rest) 'error))
           (let ((child (car rest))
                 (input (cdr rest)))

             (emmet-aif (emmet-regex "^" input '(0 1))
                        (let ((input (elt it 1)))
                          (emmet-run
                           emmet-subexpr
                           `((sibling ,(car (listing items child "")) ,expr) . ,input)
                           (listing items child input)))
                        (listing items child input)))
         '(error "expected child")))
     (emmet-run emmet-tag
                (emmet-child expr input)
                '(error "expected parent")))))

(defun emmet-child-sans (parent input)
  (emmet-parse ">" 1 ">"
                   (emmet-run emmet-subexpr
                                  it
                                  '(error "expected child"))))

(defun emmet-child (parent input)
  (emmet-parse ">" 1 ">"
                   (emmet-run emmet-subexpr
                                  (let ((child expr))
                                    (emmet-aif (emmet-regex "^" input '(0 1))
                                                   (let ((input (elt it 1)))
                                                     (emmet-run emmet-subexpr
                                                                    `((sibling (parent-child ,parent ,child) ,expr) . ,input)
                                                                    `((parent-child ,parent ,child) . ,input)))
                                                   `((parent-child ,parent ,child) . ,input)))
                                  '(error "expected child"))))

(defun emmet-sibling (input)
  (emmet-por emmet-pexpr emmet-multiplier
                 it
                 (emmet-run emmet-tag
                                it
                                (emmet-run emmet-text
                                               it
                                               '(error "expected sibling")))))

(defun emmet-siblings (input)
  "Parse an e+e expression, where e is an tag or a pexpr."
  (emmet-run emmet-sibling
                 (let ((parent expr))
                   (emmet-parse
                    "\\+" 1 "+"
                    (emmet-run
                     emmet-subexpr
                     (let ((child expr))
                       `((sibling ,parent ,child) . ,input))
                     (emmet-expand parent input))))
                 '(error "expected first sibling")))

(defun emmet-expand (parent input)
  "Parse an e+ expression, where e is an expandable tag"
  (let* ((parent-tag (car (cadr parent))))
    (setf (caadr parent) (concat parent-tag "+"))
    (cl-destructuring-bind (parent . input)
        (emmet-expand-tag-alias parent input)
      (emmet-pif (emmet-parse "+\\(.*\\)" 1 "+expr"
                              (emmet-subexpr (elt it 1)))
                 `((sibling ,parent ,@it))
                 `(,parent . ,input)))))

(defun emmet-name (input)
  "Parse a class or identifier name, e.g. news, footer, mainimage"
  (emmet-parse "\\([a-zA-Z$@][a-zA-Z0-9$@_:-]*\\)" 2 "class or identifer name"
                   `((name . ,(emmet-split-numbering-expressions
                               (elt it 1))) . ,input)))

(defun emmet-class (input)
  "Parse a classname expression, e.g. .foo"
  (emmet-parse "\\." 1 "."
                   (emmet-run emmet-name
                                  `((class ,expr) . ,input)
                                  '(error "expected class name"))))
(defun emmet-identifier (input)
  "Parse an identifier expression, e.g. #foo"
  (emmet-parse "#" 1 "#"
                   (emmet-run emmet-name
                                  `((identifier . ,expr) . ,input))))

(defun emmet-classes (input)
  "Parse many classes."
  (emmet-run emmet-class
                 (emmet-pif (emmet-classes input)
                                `((classes . ,(cons expr (cdar it))) . ,(cdr it))
                                `((classes . ,(list expr)) . ,input))
                 '(error "expected class")))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Zen coding transformer from AST to string

(defvar emmet-leaf-function nil
  "Function to execute when expanding a leaf node in the
  Emmet AST.")

(defvar emmet-expand-jsx-className? nil
  "Wether to use `className' when expanding `.classes'")

(defvar
 emmet-tag-settings-table
 (gethash "tags" (gethash "html" emmet-preferences)))

(defvar
  emmet-tag-snippets-table
  (gethash "snippets" (gethash "html" emmet-snippets)))

(defvar emmet-filters
  '("html" (emmet-primary-filter emmet-make-html-tag)
    "c"    (emmet-primary-filter emmet-make-commented-html-tag)
    "haml" (emmet-primary-filter emmet-make-haml-tag)
    "hic"  (emmet-primary-filter emmet-make-hiccup-tag)
    "e"    (emmet-escape-xml)))

(defun emmet-instantiate-lorem-expression (input)
  (if input
      (if (consp input)
          (if (and (eql (car input) 'lorem) (numberp (cadr input)))
              (emmet-lorem-generate (cadr input))
            (cons (emmet-instantiate-lorem-expression (car input))
                  (emmet-instantiate-lorem-expression (cdr input))))
        input)))

(defun emmet-primary-filter (input proc)
  "Process filter that needs to be executed first, ie. not given output from other filter."
  (if (listp input)
      (let ((tag-maker (cadr proc)))
        (emmet-transform-ast
         (emmet-instantiate-lorem-expression input)
         tag-maker))
    nil))

(defun emmet-process-filter (filters input)
  "Process filters, chain one filter output as the input of the next filter."
  (let ((filter-data (member (car filters) emmet-filters))
        (more-filters (cdr filters)))
    (if filter-data
        (let* ((proc   (cadr filter-data))
               (fun    (car proc))
               (filter-output (funcall fun input proc)))
          (if more-filters
              (emmet-process-filter more-filters filter-output)
            filter-output))
      nil)))

(defun emmet-make-tag (tag-maker tag-info &optional content)
  "Extract tag info and pass them to tag-maker."
  (let* ((name      (pop tag-info))
         (has-body? (pop tag-info))
         (id        (pop tag-info))
         (classes   (pop tag-info))
         (props     (pop tag-info))
         (txt       (pop tag-info))
         (settings  (gethash name emmet-tag-settings-table))
         (self-closing?
          (and (not (or txt content))
               (or  (not has-body?)
                    (and settings (gethash "selfClosing" settings))))))
    (funcall tag-maker name has-body? id classes props txt settings
             (if content content
               (if (and emmet-leaf-function (not self-closing?))
                   (funcall emmet-leaf-function))))))

(defun emmet-hash-to-list (hash &optional proc)
  (unless proc (setq proc #'cons))
  (cl-loop for key being the hash-keys of hash using (hash-values val)
           collect (funcall proc key val)))

(defun emmet-merge-tag-props (default-table tag-props)
  (if default-table
      (let ((tbl (copy-hash-table default-table)))
        (cl-loop for prop in tag-props do
                 (puthash (symbol-name (car prop)) (cadr prop) tbl))
        (emmet-hash-to-list tbl 'list))
    tag-props))

(defun emmet-html-snippets-instantiate-lambda (src)
  (let ((lines (mapcar
                #'(lambda (src)
                    (if (string-match "^\\(.*\\)${child}\\(.*\\)$" src)
                        (mapcar (lambda (i)
                                  (match-string i src))
                                '(1 2))
                      (list src)))
                (split-string src "\n"))))
    (cl-labels
        ((iter
          (l m a b)
          (if l
              (if (< 1 (length (car l)))
                  (iter (cdr l)
                        'b
                        (cons (caar l)  a)
                        (cons (cadar l) b))
                (if (eql m 'a)
                    (iter (cdr l) m (cons (caar l) a) b)
                  (iter (cdr l) m a (cons (caar l) b))))
            (if b
                `(lambda (contents)
                   (concat
                    ,(string-join (reverse a) "\n")
                    contents
                    ,(string-join (reverse b) "\n")))
              `(lambda (contents)
                 (concat
                  ,(string-join (reverse a) "\n")
                  contents))))))
      (eval (iter lines 'a nil nil)))))

(defun emmet-make-html-tag (tag-name tag-has-body? tag-id tag-classes tag-props tag-txt settings content)
  "Create HTML markup string"
  (emmet-aif
   (gethash tag-name emmet-tag-snippets-table)

   (let ((fn (if (stringp it)
                 (emmet-html-snippets-instantiate-lambda it)
               it)))
     (prog1
         (funcall fn content)
       (puthash tag-name fn emmet-tag-snippets-table)))

   (let* ((id           (emmet-concat-or-empty " id=\"" tag-id "\""))
          (class-attr  (if emmet-expand-jsx-className? " className=\"" " class=\""))
          (classes      (emmet-mapconcat-or-empty class-attr tag-classes " " "\""))
          (props        (let* ((tag-props-default
                                (and settings (gethash "defaultAttr" settings)))
                               (merged-tag-props
                                (emmet-merge-tag-props
                                 tag-props-default
                                 tag-props)))
                          (emmet-mapconcat-or-empty
                           " " merged-tag-props " " nil
                           (lambda (prop)
                             (let ((key (car prop)))
                               (concat (if (symbolp key) (symbol-name key) key)
                                       "=\"" (cadr prop) "\""))))))
          (content-multiline? (and content (string-match "\n" content)))
          (block-tag?         (and settings (gethash "block" settings)))
          (self-closing?      (and (not (or tag-txt content))
                                   (or (not tag-has-body?)
                                       (and settings (gethash "selfClosing" settings)))))
	  (block-indentation? (or content-multiline? (and block-tag? content)))
          (lf                 (if block-indentation? "\n")))
     (concat "<" tag-name id classes props
             (if self-closing?
                 (concat emmet-self-closing-tag-style ">")
               (concat ">"
                       (if tag-txt
                           (if block-indentation?
                               (emmet-indent tag-txt)
                             tag-txt))
                       (if content
                           (if block-indentation?
                               (emmet-indent content)
                             content))
                       lf
                       "</" tag-name ">"))))))

(defun emmet-make-commented-html-tag (tag-name tag-has-body? tag-id tag-classes tag-props tag-txt settings content)
  "Create HTML markup string with extra comments for elements with #id or .classes"
  (let ((body (emmet-make-html-tag tag-name tag-has-body? tag-id tag-classes tag-props tag-txt settings content)))
    (if (or tag-id tag-classes)
        (let ((id      (emmet-concat-or-empty "#" tag-id))
              (classes (emmet-mapconcat-or-empty "." tag-classes ".")))
          (concat "<!-- " id classes " -->\n"
                  body
                  "\n<!-- /" id classes " -->"))
      body)))

(defun emmet-make-haml-tag (tag-name tag-has-body? tag-id tag-classes tag-props tag-txt settings content)
  "Create HAML string"
  (let ((name    (if (and (equal tag-name "div")
                          (or tag-id tag-classes))
                     ""
                   (concat "%" tag-name)))
        (id      (emmet-concat-or-empty "#" tag-id))
        (classes (emmet-mapconcat-or-empty "." tag-classes "."))
        (props   (emmet-mapconcat-or-empty
                  "{" tag-props ", " "}"
                  (lambda (prop)
                    (concat ":" (symbol-name (car prop)) " => \"" (cadr prop) "\"")))))
    (concat name id classes props
            (if tag-txt
                (emmet-indent tag-txt))
            (if content
                (emmet-indent content)))))

(defun emmet-make-hiccup-tag (tag-name tag-has-body? tag-id tag-classes tag-props tag-txt settings content)
  "Create Hiccup string"
  (let* ((id      (emmet-concat-or-empty "#" tag-id))
         (classes (emmet-mapconcat-or-empty "." tag-classes "."))
         (props   (emmet-mapconcat-or-empty
                   " {" tag-props ", " "}"
                   (lambda (prop)
                     (concat ":" (symbol-name (car prop)) " \"" (cadr prop) "\""))))
         (content-multiline? (and content (string-match "\n" content)))
         (block-tag? (and settings (gethash "block" settings)))
         (block-indentation? (or content-multiline? (and block-tag? content))))
    (concat "[:" tag-name id classes props
            (if tag-txt
                (let ((tag-txt-quoted (concat "\"" tag-txt "\"")))
                  (if block-indentation?
                      (emmet-indent tag-txt-quoted)
                    (concat " " tag-txt-quoted))))
            (if content
                (if block-indentation?
                    (emmet-indent content)
                  (concat " " content)))
            "]")))

(defun emmet-make-text (tag-maker text)
  (cond
   ((eq tag-maker 'emmet-make-hiccup-tag)
    (concat "\"" text "\""))
   (t text)))

(defun emmet-concat-or-empty (prefix body &optional suffix)
  "Return prefixed suffixed text or empty string."
  (if body
      (concat prefix body suffix)
    ""))

(defun emmet-mapconcat-or-empty (prefix list-body delimiter &optional suffix map-fun)
  "Return prefixed suffixed mapconcated text or empty string."
  (if list-body
      (let* ((mapper (if map-fun map-fun 'identity))
             (body (mapconcat mapper list-body delimiter)))
        (concat prefix body suffix))
    ""))

(defun emmet-escape-xml (input proc)
  "Escapes XML-unsafe characters: <, > and &."
  (replace-regexp-in-string
   "<" "&lt;"
   (replace-regexp-in-string
    ">" "&gt;"
    (replace-regexp-in-string
     "&" "&amp;"
     (if (stringp input)
         input
       (emmet-process-filter (emmet-default-filter) input))))))

(defun emmet-html-transform (input)
  (let ((ast (car (emmet-expr input))))
    (when (not (eq ast 'error))
      (emmet-transform-ast-with-filters ast))))

(defun emmet-transform-ast-with-filters (ast-with-filters)
  "Transform AST (containing filter data) into string."
  (let ((filters (cadr ast-with-filters))
        (ast (caddr ast-with-filters)))
    (emmet-process-filter filters ast)))

(defun emmet-transform-ast (ast tag-maker)
  "Transform AST (without filter data) into string."
  (let ((type (car ast)))
    (cond
     ((eq type 'list)
      (mapconcat (lexical-let ((make-tag-fun tag-maker))
                   #'(lambda (sub-ast)
                       (emmet-transform-ast sub-ast make-tag-fun)))
                 (cadr ast)
                 "\n"))
     ((eq type 'tag)
      (emmet-make-tag tag-maker (cadr ast)))
     ((eq type 'text)
      (emmet-make-text tag-maker (cadr ast)))
     ((eq type 'parent-child)
      (let ((parent (cadadr ast))
            (children (emmet-transform-ast (caddr ast) tag-maker)))
        (emmet-make-tag tag-maker parent children)))
     ((eq type 'sibling)
      (let ((sib1 (emmet-transform-ast (cadr ast) tag-maker))
            (sib2 (emmet-transform-ast (caddr ast) tag-maker)))
        (concat sib1 "\n" sib2))))))

;; Indents text rigidly by inserting spaces
;; Only matters if emmet-indent-after-insert is set to nil
(defun emmet-indent (text)
  "Indent the text"
  (if text
      (replace-regexp-in-string "\n" (concat "\n" (make-string emmet-indentation ?\ )) (concat "\n" text))
    nil))
(defvar emmet-lorem-words
  '("lorem" "ipsum" "dolor" "sit" "amet," "consectetur" "adipiscing" "elit" "ut" "aliquam," "purus" "sit" "amet" "luctus" "venenatis,"
    "lectus" "magna" "fringilla" "urna," "porttitor" "rhoncus" "dolor" "purus" "non" "enim" "praesent" "elementum" "facilisis" "leo,"
    "vel" "fringilla" "est" "ullamcorper" "eget" "nulla" "facilisi" "etiam" "dignissim" "diam" "quis" "enim" "lobortis" "scelerisque"
    "fermentum" "dui" "faucibus" "in" "ornare" "quam" "viverra" "orci" "sagittis" "eu" "volutpat" "odio" "facilisis" "mauris" "sit" "amet"
    "massa" "vitae" "tortor" "condimentum" "lacinia" "quis" "vel" "eros" "donec" "ac" "odio" "tempor" "orci" "dapibus" "ultrices" "in"
    "iaculis" "nunc" "sed" "augue" "lacus," "viverra" "vitae" "congue" "eu," "consequat" "ac" "felis" "donec" "et" "odio" "pellentesque"
    "diam" "volutpat" "commodo" "sed" "egestas" "egestas" "fringilla" "phasellus" "faucibus" "scelerisque" "eleifend" "donec" "pretium"
    "vulputate" "sapien" "nec" "sagittis" "aliquam" "malesuada" "bibendum" "arcu" "vitae" "elementum" "curabitur" "vitae" "nunc" "sed"
    "velit" "dignissim" "sodales" "ut" "eu" "sem" "integer" "vitae" "justo" "eget" "magna" "fermentum" "iaculis" "eu" "non" "diam"
    "phasellus" "vestibulum" "lorem" "sed" "risus" "ultricies" "tristique" "nulla" "aliquet" "enim" "tortor," "at" "auctor" "urna" "nunc"
    "id" "cursus" "metus" "aliquam" "eleifend" "mi" "in" "nulla" "posuere" "sollicitudin" "aliquam" "ultrices" "sagittis" "orci," "a"
    "scelerisque" "purus" "semper" "eget" "duis" "at" "tellus" "at" "urna" "condimentum" "mattis" "pellentesque" "id" "nibh" "tortor,"
    "id" "aliquet" "lectus" "proin" "nibh" "nisl," "condimentum" "id" "venenatis" "a," "condimentum" "vitae" "sapien" "pellentesque"
    "habitant" "morbi" "tristique" "senectus" "et" "netus" "et" "malesuada" "fames" "ac" "turpis" "egestas" "sed" "tempus," "urna" "et"
    "pharetra" "pharetra," "massa" "massa" "ultricies" "mi," "quis" "hendrerit" "dolor" "magna" "eget" "est" "lorem" "ipsum" "dolor" "sit"
    "amet," "consectetur" "adipiscing" "elit" "pellentesque" "habitant" "morbi" "tristique" "senectus" "et" "netus" "et" "malesuada" "fames"
    "ac" "turpis" "egestas" "integer" "eget" "aliquet" "nibh" "praesent" "tristique" "magna" "sit" "amet" "purus" "gravida" "quis" "blandit"
    "turpis" "cursus" "in" "hac" "habitasse" "platea" "dictumst" "quisque" "sagittis," "purus" "sit" "amet" "volutpat" "consequat," "mauris"
    "nunc" "congue" "nisi," "vitae" "suscipit" "tellus" "mauris" "a" "diam" "maecenas" "sed" "enim" "ut" "sem" "viverra" "aliquet" "eget"
    "sit" "amet" "tellus" "cras" "adipiscing" "enim" "eu" "turpis" "egestas" "pretium" "aenean" "pharetra," "magna" "ac" "placerat"
    "vestibulum," "lectus" "mauris" "ultrices" "eros," "in" "cursus" "turpis" "massa" "tincidunt" "dui" "ut" "ornare" "lectus" "sit" "amet"
    "est" "placerat" "in" "egestas" "erat" "imperdiet" "sed" "euismod" "nisi" "porta" "lorem" "mollis" "aliquam" "ut" "porttitor" "leo" "a"
    "diam" "sollicitudin" "tempor" "id" "eu" "nisl" "nunc" "mi" "ipsum," "faucibus" "vitae" "aliquet" "nec," "ullamcorper" "sit" "amet"
    "risus" "nullam" "eget" "felis" "eget" "nunc" "lobortis" "mattis" "aliquam" "faucibus" "purus" "in" "massa" "tempor" "nec" "feugiat"
    "nisl" "pretium" "fusce" "id" "velit" "ut" "tortor" "pretium" "viverra" "suspendisse" "potenti" "nullam" "ac" "tortor" "vitae" "purus"
    "faucibus" "ornare" "suspendisse" "sed" "nisi" "lacus," "sed" "viverra" "tellus" "in" "hac" "habitasse" "platea" "dictumst" "vestibulum"
    "rhoncus" "est" "pellentesque" "elit" "ullamcorper" "dignissim" "cras" "tincidunt" "lobortis" "feugiat" "vivamus" "at" "augue" "eget"
    "arcu" "dictum" "varius" "duis" "at" "consectetur" "lorem" "donec" "massa" "sapien," "faucibus" "et" "molestie" "ac," "feugiat" "sed"
    "lectus" "vestibulum" "mattis" "ullamcorper" "velit" "sed" "ullamcorper" "morbi" "tincidunt" "ornare" "massa," "eget" "egestas" "purus"
    "viverra" "accumsan" "in" "nisl" "nisi," "scelerisque" "eu" "ultrices" "vitae," "auctor" "eu" "augue" "ut" "lectus" "arcu," "bibendum"
    "at" "varius" "vel," "pharetra" "vel" "turpis" "nunc" "eget" "lorem" "dolor," "sed" "viverra" "ipsum" "nunc" "aliquet" "bibendum" "enim,"
    "facilisis" "gravida" "neque" "convallis" "a" "cras" "semper" "auctor" "neque," "vitae" "tempus" "quam" "pellentesque" "nec" "nam"
    "aliquam" "sem" "et" "tortor" "consequat" "id" "porta" "nibh" "venenatis" "cras" "sed" "felis" "eget" "velit" "aliquet" "sagittis"
    "id" "consectetur" "purus" "ut" "faucibus" "pulvinar" "elementum" "integer" "enim" "neque," "volutpat" "ac" "tincidunt" "vitae,"
    "semper" "quis" "lectus" "nulla" "at" "volutpat" "diam" "ut" "venenatis" "tellus" "in" "metus" "vulputate" "eu" "scelerisque" "felis"
    "imperdiet" "proin" "fermentum" "leo" "vel" "orci" "porta" "non" "pulvinar" "neque" "laoreet" "suspendisse" "interdum" "consectetur"
    "libero," "id" "faucibus" "nisl" "tincidunt" "eget" "nullam" "non" "nisi" "est," "sit" "amet" "facilisis" "magna" "etiam" "tempor,"
    "orci" "eu" "lobortis" "elementum," "nibh" "tellus" "molestie" "nunc," "non" "blandit" "massa" "enim" "nec" "dui" "nunc" "mattis"
    "enim" "ut" "tellus" "elementum" "sagittis" "vitae" "et" "leo" "duis" "ut" "diam" "quam" "nulla" "porttitor" "massa" "id" "neque"
    "aliquam" "vestibulum" "morbi" "blandit" "cursus" "risus," "at" "ultrices" "mi" "tempus" "imperdiet" "nulla" "malesuada" "pellentesque"
    "elit" "eget" "gravida" "cum" "sociis" "natoque" "penatibus" "et" "magnis" "dis" "parturient" "montes," "nascetur" "ridiculus" "mus"
    "mauris" "vitae" "ultricies" "leo" "integer" "malesuada" "nunc" "vel" "risus" "commodo" "viverra" "maecenas" "accumsan," "lacus" "vel"
    "facilisis" "volutpat," "est" "velit" "egestas" "dui," "id" "ornare" "arcu" "odio" "ut" "sem" "nulla" "pharetra" "diam" "sit" "amet"
    "nisl" "suscipit" "adipiscing" "bibendum" "est" "ultricies" "integer" "quis" "auctor" "elit" "sed" "vulputate" "mi" "sit" "amet" "mauris"
    "commodo" "quis" "imperdiet" "massa" "tincidunt" "nunc" "pulvinar" "sapien" "et" "ligula" "ullamcorper" "malesuada" "proin" "libero"
    "nunc," "consequat" "interdum" "varius" "sit" "amet," "mattis" "vulputate" "enim" "nulla" "aliquet" "porttitor" "lacus," "luctus"
    "accumsan" "tortor" "posuere" "ac" "ut" "consequat" "semper" "viverra" "nam" "libero" "justo," "laoreet" "sit" "amet" "cursus" "sit"
    "amet," "dictum" "sit" "amet" "justo" "donec" "enim" "diam," "vulputate" "ut" "pharetra" "sit" "amet," "aliquam" "id" "diam" "maecenas"
    "ultricies" "mi" "eget" "mauris" "pharetra" "et" "ultrices" "neque" "ornare" "aenean" "euismod" "elementum" "nisi," "quis" "eleifend"
    "quam" "adipiscing" "vitae" "proin" "sagittis," "nisl" "rhoncus" "mattis" "rhoncus," "urna" "neque" "viverra" "justo," "nec" "ultrices"
    "dui" "sapien" "eget" "mi" "proin" "sed" "libero" "enim," "sed" "faucibus" "turpis" "in" "eu" "mi" "bibendum" "neque" "egestas" "congue"
    "quisque" "egestas" "diam" "in" "arcu" "cursus" "euismod" "quis" "viverra" "nibh" "cras" "pulvinar" "mattis" "nunc," "sed" "blandit"
    "libero" "volutpat" "sed" "cras" "ornare" "arcu" "dui" "vivamus" "arcu" "felis," "bibendum" "ut" "tristique" "et," "egestas" "quis"
    "ipsum" "suspendisse" "ultrices" "gravida" "dictum" "fusce" "ut" "placerat" "orci" "nulla" "pellentesque" "dignissim" "enim," "sit"
    "amet" "venenatis" "urna" "cursus" "eget" "nunc" "scelerisque" "viverra" "mauris," "in" "aliquam" "sem" "fringilla" "ut" "morbi"
    "tincidunt" "augue" "interdum" "velit" "euismod" "in" "pellentesque" "massa" "placerat" "duis" "ultricies" "lacus" "sed" "turpis"
    "tincidunt" "id" "aliquet" "risus" "feugiat" "in" "ante" "metus," "dictum" "at" "tempor" "commodo," "ullamcorper" "a" "lacus" "vestibulum"
    "sed" "arcu" "non" "odio" "euismod" "lacinia" "at" "quis" "risus" "sed" "vulputate" "odio" "ut" "enim" "blandit" "volutpat" "maecenas"
    "volutpat" "blandit" "aliquam" "etiam" "erat" "velit," "scelerisque" "in" "dictum" "non," "consectetur" "a" "erat" "nam" "at" "lectus"
    "urna" "duis" "convallis" "convallis" "tellus," "id" "interdum" "velit" "laoreet" "id" "donec" "ultrices" "tincidunt" "arcu," "non"
    "sodales" "neque" "sodales" "ut" "etiam" "sit" "amet" "nisl" "purus," "in" "mollis" "nunc" "sed" "id" "semper" "risus" "in" "hendrerit"
    "gravida" "rutrum" "quisque" "non" "tellus" "orci," "ac" "auctor" "augue" "mauris" "augue" "neque," "gravida" "in" "fermentum" "et,"
    "sollicitudin" "ac" "orci" "phasellus" "egestas" "tellus" "rutrum" "tellus" "pellentesque" "eu" "tincidunt" "tortor" "aliquam" "nulla"
    "facilisi" "cras" "fermentum," "odio" "eu" "feugiat" "pretium," "nibh" "ipsum" "consequat" "nisl," "vel" "pretium" "lectus" "quam" "id"
    "leo" "in" "vitae" "turpis" "massa" "sed" "elementum" "tempus" "egestas" "sed" "sed" "risus" "pretium" "quam" "vulputate" "dignissim"
    "suspendisse" "in" "est" "ante" "in" "nibh" "mauris," "cursus" "mattis" "molestie" "a," "iaculis" "at" "erat" "pellentesque" "adipiscing"
    "commodo" "elit," "at" "imperdiet" "dui" "accumsan" "sit" "amet" "nulla" "facilisi" "morbi" "tempus" "iaculis" "urna," "id" "volutpat"
    "lacus" "laoreet" "non" "curabitur" "gravida" "arcu" "ac" "tortor" "dignissim" "convallis" "aenean" "et" "tortor" "at" "risus" "viverra"
    "adipiscing" "at" "in" "tellus" "integer" "feugiat" "scelerisque" "varius" "morbi" "enim" "nunc," "faucibus" "a" "pellentesque" "sit"
    "amet," "porttitor" "eget" "dolor" "morbi" "non" "arcu" "risus," "quis" "varius" "quam" "quisque" "id" "diam" "vel" "quam" "elementum"
    "pulvinar" "etiam" "non" "quam" "lacus" "suspendisse" "faucibus" "interdum" "posuere" "lorem" "ipsum" "dolor" "sit" "amet," "consectetur"
    "adipiscing" "elit" "duis" "tristique" "sollicitudin" "nibh" "sit" "amet" "commodo" "nulla" "facilisi" "nullam" "vehicula" "ipsum" "a"
    "arcu" "cursus" "vitae" "congue" "mauris" "rhoncus" "aenean" "vel" "elit" "scelerisque" "mauris" "pellentesque" "pulvinar" "pellentesque"
    "habitant" "morbi" "tristique" "senectus" "et" "netus" "et" "malesuada" "fames" "ac" "turpis" "egestas" "maecenas" "pharetra" "convallis"
    "posuere" "morbi" "leo" "urna," "molestie" "at" "elementum" "eu," "facilisis" "sed" "odio" "morbi" "quis" "commodo" "odio" "aenean" "sed"
    "adipiscing" "diam" "donec" "adipiscing" "tristique" "risus" "nec" "feugiat" "in" "fermentum" "posuere" "urna" "nec" "tincidunt" "praesent"
    "semper" "feugiat" "nibh" "sed" "pulvinar" "proin" "gravida" "hendrerit" "lectus" "a" "molestie"))

(defun emmet-random-range (min max)
  (+ min (random (+ (- max min) 1))))

(defun emmet-lorem-choice-words (count &optional s)
  (let* ((l (length emmet-lorem-words))
         (s (if s s (random l)))
         (f (+ s count))
         (e (if (< l f) l f)))
    (append
     (cl-subseq emmet-lorem-words s e)
     (if (= e l) (emmet-lorem-choice-words (- f l) 0)))))

(defvar emmet-lorem-min-sentence 5)

(defvar emmet-lorem-max-sentence 30)

(defun emmet-upcase-first (s)
  (concat (upcase (cl-subseq s 0 1)) (cl-subseq s 1)))

(defun emmet-lorem-generate (count)
  (if (<= count 0) ""
    (let ((sl (if (< count emmet-lorem-max-sentence) count
                (emmet-random-range
                 emmet-lorem-min-sentence
                 (min (- count emmet-lorem-min-sentence)
                      emmet-lorem-max-sentence))))
          (last (let ((r (random 4)))
                  (if (< 1 r) "." (if (< 0 r) "?" "!")))))
      (let ((words (let ((w (emmet-lorem-choice-words sl)))
                     (let ((l (car (last w))))
                       (if (string-equal (substring l -1) ",")
                           (append (cl-subseq w 0 -1) (list (substring l 0 -1)))
                         w)))))
        (concat (emmet-upcase-first (string-join words " ")) last
                (let ((next (emmet-lorem-generate (- count sl))))
                  (if (string-equal next "") ""
                    (concat " " next))))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;;; CSS abbrev:

(defvar
  emmet-css-unit-aliases
  (gethash "unitAliases" (gethash "css" emmet-preferences)))
(defun emmet-css-arg-number (input)
  (emmet-parse
   " *\\(\\(?:-\\|\\)[0-9.]+\\)\\(-\\|[A-Za-z]*\\)" 3 "css number arguments"
   (cons (list (elt it 1)
               (let ((unit (elt it 2)))
                 (if (= (length unit) 0)
                     (if (cl-find ?. (elt it 1)) "em" "px")
                   (gethash unit emmet-css-unit-aliases unit))))
         input)))

(defvar
  emmet-css-color-shorten-if-possible
  (gethash "shortenIfPossible" (gethash "color" (gethash "css" emmet-preferences))))
(defvar
  emmet-css-color-case
  (gethash "case" (gethash "color" (gethash "css" emmet-preferences))))
(defvar
  emmet-css-color-trailing-aliases
  (gethash "trailingAliases" (gethash "color" (gethash "css" emmet-preferences))))
(defun emmet-css-arg-color (input)
  (emmet-parse
   (concat " *#\\([0-9a-fA-F]\\{1,6\\}\\)\\(rgb\\|\\)\\(["
           (string-join
            (hash-table-keys emmet-css-color-trailing-aliases) "")
           "]\\|\\)")
   4 "css color argument"
   (let ((color
          (let* ((n (elt it 1))
                 (l (length n)))
            (substring
             (cond ((= l 1) (concat (make-list 6 (string-to-char n))))
                   ((= l 2) (concat n n n))
                   ((= l 3) (concat
                             (cl-loop for c in (string-to-list n)
                                      append (list c c))))
                   (t (concat n n)))
             0 6))))
     (cons
      (let ((rgb-mode (string= (elt it 2) "rgb")))
        (if rgb-mode
            (format "rgb(%d,%d,%d)"
                    (string-to-number (substring color 0 2) 16)
                    (string-to-number (substring color 2 4) 16)
                    (string-to-number (substring color 4 6) 16))
          (concat
           "#"
           (let ((filter (cond ((string= emmet-css-color-case "auto") #'identity)
                               ((string= emmet-css-color-case "up")   #'upcase)
                               (t                                         #'downcase))))
             (funcall
              filter
              (if (and emmet-css-color-shorten-if-possible
                       (eql (aref color 0) (aref color 1))
                       (eql (aref color 2) (aref color 3))
                       (eql (aref color 4) (aref color 5)))
                  (concat (mapcar #'(lambda (i) (aref color i)) '(0 2 4)))
                color))))))
      (if (< 0 (length (elt it 3)))
          (cons (gethash (elt it 3) emmet-css-color-trailing-aliases) input)
        input)))))

(defun emmet-css-arg-something (input)
  (emmet-parse
   " *\\([^ ]+\\)" 2 "css argument"
   (cons (elt it 1) input)))

(defun emmet-css-parse-arg (input)
  (emmet-run emmet-css-arg-number it
                 (emmet-run emmet-css-arg-color it
                                (emmet-run emmet-css-arg-something it
                                               (if (equal input "")
                                                   it
                                                 (cons input ""))))))

(defun emmet-css-important-p (input)
  (let ((len (length input)))
    (and (< 0 len)
         (char-equal (aref input (1- len)) ?!))))

(defun emmet-css-parse-args (args)
  (when args
    (let ((rt nil))
      (cl-loop
       (emmet-pif
        (emmet-css-parse-arg args)
        (cl-loop for i on it do (push (car i) rt)
                 while (consp (cdr i))
                 finally (setq args (cdr i)))
        (cl-return (nreverse rt)))))))

(defun emmet-css-split-args (exp)
  (emmet-aif
   (string-match "\\(?:[ #0-9$]\\|-[0-9]\\)" exp)
   (list (substring exp 0 it) (substring exp it))
   (list exp nil)))

(defun emmet-css-split-vendor-prefixes (input)
  (emmet-parse
   "\\(-[wmso]+-\\|-\\|\\)\\(.*\\)" 3 "css vendor prefixes"
   (list (elt it 2)
         (let ((vp (elt it 1)))
           (if (not (string= vp ""))
               (if (string= vp "-") 'auto
                 (string-to-list (cl-subseq vp 1 -1))))))))

(defun emmet-css-subexpr (exp)
  (let* ((importantp (emmet-css-important-p exp)))
    (cl-destructuring-bind (exp vp)
        (emmet-css-split-vendor-prefixes exp)
      (cl-destructuring-bind (key args)
          (emmet-css-split-args (if importantp (cl-subseq exp 0 -1) exp))
        `(,key ,vp
               ,importantp
               ,@(emmet-css-parse-args args))))))

(defun emmet-css-toknize (str)
  (let* ((i (split-string str "+"))
         (rt nil))
    (cl-loop
     (let ((f (cl-first i))
           (s (cl-second i)))
       (if f
           (if (and s (or (string= s "")
                          (string-match "^\\(?:[ #0-9$]\\|-[0-9]\\)" s)))
               (progn
                 (setf rt (cons (concat f "+" s) rt))
                 (setf i (cddr i)))
             (progn
               (setf rt (cons f rt))
               (setf i (cdr i))))
         (cl-return (nreverse rt)))))))

(defun emmet-css-expr (input)
  (mapcar #'emmet-css-subexpr
          (emmet-css-toknize input)))

(defvar
  emmet-css-snippets
  (gethash "snippets" (gethash "css" emmet-snippets)))

(defvar
  emmet-sass-snippets
  (gethash "snippets" (gethash "sass" emmet-snippets)))

(defvar
  emmet-css-unitless-properties
  (gethash "unitlessProperties" (gethash "css" emmet-preferences)))

(defvar
  emmet-css-unitless-properties-regex
  (concat "^\\(:?" (string-join
                    emmet-css-unitless-properties "\\|")
          "\\):.*$"))

(defun emmet-css-instantiate-lambda (str)
  (cl-flet ((insert-space-between-name-and-body
             (str)
             (if (string-match "^\\([a-z-]+:\\)\\(.+\\)$" str)
                 (string-join
                  (mapcar (lambda (ref) (match-string ref str)) '(1 2)) " ")
               str))
            (split-string-to-body
             (str args-sym)
             (let ((rt '(concat)) (idx-max 0))
               (cl-loop for i from 0 to 255 do
                        (emmet-aif
                         (string-match "\\(?:|\\|${\\(?:\\([0-9]\\)\\|\\)\\(?::\\(.+?\\)\\|\\)}\\)" str)
                         (cl-destructuring-bind (mat idx def)
                             (mapcar (lambda (ref) (match-string ref str)) '(0 1 2))
                           (setf rt
                                 `((or
                                    (nth ,(let ((cur-idx (if idx (1- (string-to-number idx)) i)))
                                            (setf idx-max (max cur-idx idx-max)))
                                         ,args-sym)
                                    ,(or def ""))
                                   ,(substring str 0 it) ;; ordered to reverse
                                   ,@rt))
                           (setf str (substring str (+ it (length mat)))))
                         ;; don't use nreverse. cause bug in emacs-lisp.
                         (cl-return (cons idx-max (reverse (cons str rt)))))))))
    (let ((args (gensym))
          (str  (insert-space-between-name-and-body str)))
      (cl-destructuring-bind (idx-max . body) (split-string-to-body str args)
        (eval
         `(lambda (&rest ,args)
            (progn
              (when (nthcdr ,idx-max ,args)
                (setf (nthcdr ,idx-max ,args)
                      (list (string-join
                             (nthcdr ,idx-max ,args) " "))))
              ,body)))))))

(defvar
  emmet-vendor-prefixes-properties
  (gethash "vendorPrefixesProperties" (gethash "css" emmet-preferences)))
(defvar
  emmet-vendor-prefixes-default
  (list "webkit" "moz" "ms" "o"))
(defun emmet-css-transform-vendor-prefixes (line vp)
  (let ((key (cl-subseq line 0 (or (cl-position ?: line) (length line)))))
    (let ((vps (if (eql vp 'auto)
                   (gethash key
                            emmet-vendor-prefixes-properties
                            emmet-vendor-prefixes-default)
                 (mapcar (lambda (v)
                           (cond ((= v ?w) "webkit")
                                 ((= v ?m) "moz")
                                 ((= v ?s) "ms")
                                 ((= v ?o) "o")))
                         vp))))
      (string-join
       (append (mapcar (lambda (v) (concat "-" v "-" line)) vps)
               (list line))
       "\n"))))

(defun emmet-css-transform-exprs (exprs)
  (string-join
   (mapcar
    #'(lambda (expr)
        (let*
	    ((hash-map (if emmet-use-sass-syntax emmet-sass-snippets emmet-css-snippets))
	     (basement
	      (emmet-aif
	       (or (gethash (car expr) hash-map) (gethash (car expr) emmet-css-snippets))
	       (let ((set it) (fn nil) (unitlessp nil))
		 (if (stringp set)
		     (progn
		       ;; new pattern
		       ;; creating print function
		       (setf fn (emmet-css-instantiate-lambda set))
		       ;; get unitless or no
		       (setf unitlessp
			     (not (null (string-match
					 emmet-css-unitless-properties-regex set))))
		       ;; caching
		       (puthash (car expr) (cons fn unitlessp) hash-map))
		   (progn
		     ;; cache hit.
		     (setf fn (car set))
		     (setf unitlessp (cdr set))))
		 (apply fn
			(mapcar
			 #'(lambda (arg)
			     (if (listp arg)
				 (if unitlessp (car arg)
				   (apply #'concat arg))
			       arg))
			 (cdddr expr))))
	       (concat (car expr) ": "
		       (string-join
			(mapcar #'(lambda (arg)
				    (if (listp arg) (apply #'concat arg) arg))
				(cdddr expr)) " ")
		       ";"))))
          (let ((line
                 (if (caddr expr)
                     (concat (cl-subseq basement 0 -1) " !important;")
                   basement)))
	    ;; remove trailing semicolon while editing Sass files
	    (if (and emmet-use-sass-syntax (equal ";" (cl-subseq line -1)))
		(setq line (cl-subseq line 0 -1)))
            (emmet-aif
             (cadr expr)
             (emmet-css-transform-vendor-prefixes line it)
             line))))
    exprs)
   "\n"))

(defun emmet-css-transform (input)
  (emmet-css-transform-exprs (emmet-css-expr input)))

(provide 'emmet)

;;; emmet.el ends here
