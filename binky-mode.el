;;; binky-mode.el --- Jump between points like a rabbit -*- lexical-binding: t -*-

;; Copyright (C) 2022 liuyinz

;; Author: liuyinz <liuyinz95@gmail.com>
;; Version: 0.9.0
;; Package-Requires: ((emacs "28"))
;; Keywords: convenience
;; Homepage: https://github.com/liuyinz/binky-mode

;; This file is not a part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; This package provides commands to jump between points in buffers and files.
;; Marked position, last jump position and recent buffers are all supported in
;; same mechanism like `point-to-register' and `register-to-point' but with an
;; enhanced experience.

;;; Code:

(require 'cl-lib)
(require 'cl-extra)

;;; Customize

(defgroup binky nil
  "Jump between points like a rabbit."
  :prefix "binky-"
  :group 'convenience
  :link '(url-link :tag "Repository" "https://github.com/liuyinz/binky-mode"))

(defcustom binky-mark-back ?,
  "Character used to record position before `binky-jump'.
If nil, disable the feature."
  :type '(choice character (const :tag "Disable back mark" nil))
  :group 'binky)

(defcustom binky-mark-auto
  '(?1 ?2 ?3 ?4 ?5 ?6 ?7 ?8 ?9 ?0)
  "List of printable characters to record recent used buffers.
Any self-inserting character between !(33) - ~(126) is allowed to used as
marks.  Letters, digits, punctuation, etc.
If nil, disable the feature."
  :type '(choice (repeat (choice (character :tag "Printable character as mark")))
                 (const :tag "Disable auto marks" nil))
  :group 'binky)

(defcustom binky-mark-sort-by 'recency
  "Sorting strategy for used buffers."
  :type '(choice (const :tag "Sort by recency" recency)
                 (const :tag "Sort by frequency" frequency)
                 ;; TODO
                 ;; (cosnt :tag "Sort by frecency" frecency)
                 ;; (cosnt :tag "Sort by duration" duration)
                 )
  :group 'binky)

;; ;; TODO
;; (defcustom binky-mark-distance 200
;;   "Maxmium distance bwtween points for them to be considered equal."
;;   :type 'number
;;   :group 'binky)

(defcustom binky-mark-overwrite nil
  "If non-nil, overwrite record with existing mark when call `binky-add'."
  :type 'boolean
  :group 'binky)

(defcustom binky-include-regexps
  '("\\`\\*\\(scratch\\|info\\)\\*\\'")
  "List of regexps for buffer name included in `binky-auto-alist'.
For example, buffer *scratch* is always included by default."
  :type '(repeat string)
  :group 'binky)

(defcustom binky-exclude-regexps
  '("\\`\\(\\s-\\|\\*\\).*\\'")
  "List of regexps for buffer name excluded from `binky-auto-alist'.
When a buffer name matches any of the regexps, it would not be record
automatically unless it matchs `binky-include-regexps'.  By default, all buffer
names start with '*' or ' ' are excluded."
  :type '(repeat string)
  :group 'binky)

(defcustom binky-exclude-modes
  '(xwidget-webkit-mode)
  "List of major modes which buffers belong to excluded from `binky-auto-alist'."
  :type '(repeat symbol)
  :group 'binky)

(defcustom binky-exclude-functions
  (list #'minibufferp)
  "List of predicates which buffers satisfy exclude from `binky-auto-alist'.
A predicate is a function with no arguments to check the `current-buffer'
and that must return non-nil to exclude it."
  :type '(repeat function)
  :group 'binky)

(defcustom binky-preview-delay 0.3
  "If non-nil, time to wait in seconds before popping up a preview window.
If nil, disable preview, unless \\[help] is pressed."
  :type '(choice number (const :tag "No preview unless requested" nil))
  :group 'binky)

(defcustom binky-preview-column
  '((mark     .  5)
    (name     .  26)
    (position .  12)
    (mode     .  22)
    (context  .  nil))
  "List of pairs (COLUMN . LENGTH) to display in binky preview.
COLUMN is one of five parameters of record, listed in `binky-alist'
and `binky-auto-alist'.

The `mark' represents mark.
The `name' represents buffer name of file name.
The `position' represents position.
The `mode' represents major mode.
The `context' represents substring of line where the position on.

LENGTH is a number represets COLUMN width.  If LENGTH is nil, then COLUMN would
not be truncated.  Usually, `context' column should be at the end and not
truncated."
  :type '(alist
          :key-type symbol
          :value-type '(choice number (const :tag "No limit for last column" nil))
          :options '(mark name position mode context))
  :group 'binky)

(defcustom binky-preview-ellipsis ".."
  "String used to abbreviate text in preview."
  :type 'string
  :group 'binky)

(defcustom binky-preview-show-header t
  "If non-nil, showing header in preview."
  :type 'boolean
  :group 'binky)

(defcustom binky-preview-auto-first t
  "If non-nil, showing `binky-mark-auto' first in preview buffer."
  :type 'boolean
  :group 'binky)

(defcustom binky-jump-highlight-duration 0.3
  "If non-nil, time in seconds to highlight the line jumped to.
If nil, do not highlight jumping behavior."
  :type '(choice number (const :tag "Disable jump highlight" nil))
  :group 'binky)

(defface binky-jump-highlight
  '((t :inherit highlight :extend t))
  "Face used to highlight the line jumped to."
  :group 'binky)

(defface binky-preview-header
  '((t :inherit font-lock-constant-face :underline t))
  "Face used to highlight the header in preview buffer."
  :group 'binky)

(defface binky-preview-mark-auto
  '((t :inherit font-lock-function-name-face :bold t))
  "Face used to highlight the auto mark of record in preview buffer."
  :group 'binky)

(defface binky-preview-mark-back
  '((t :inherit font-lock-type-face :bold t))
  "Face used to highlight the back mark of record in preview buffer."
  :group 'binky)

(defface binky-preview-mark
  '((t :inherit font-lock-variable-name-face :bold t))
  "Face used to highlight the mark of record in preview buffer."
  :group 'binky)

(defface binky-preview-name
  '((t :inherit default))
  "Face used to highlight the name of record in preview buffer."
  :group 'binky)

(defface binky-preview-position
  '((t :inherit font-lock-keyword-face))
  "Face used to highlight the position of record in preview buffer."
  :group 'binky)

(defface binky-preview-mode
  '((t :inherit font-lock-type-face))
  "Face used to highlight the major mode of record in preview buffer."
  :group 'binky)

(defface binky-preview-shadow
  '((t :inherit font-lock-comment-face))
  "Face used to highlight whole record of killed buffers in preview buffer."
  :group 'binky)

;;; Variables

(defvar binky-alist nil
  "List of records (MARK . INFO) set and updated by mannual.
MARK is a printable character between !(33) - ~(126).
INFO is a marker or a list of form (filename position major-mode context) use
to stores point information.")

(defvar binky-auto-alist nil
  "Alist of records (MARK . MARKER), set and updated automatically.")

(defvar binky-back-record nil
  "Record of last position before `binky-jump', set and updated automatically.")

(defvar binky-frequency-timer nil
  "Timer used to automatically increase buffer frequency.")

(defvar binky-frequency-idle 3
  "Number of seconds of idle time to wait before increasing frequency.")

(defvar-local binky-frequency 0
  "Frequency of current buffer.")

(defvar binky-preview-buffer "*Binky Preview*"
  "Buffer used to preview records in binky alists.")

(defvar-local binky-jump-overlay nil
  "Overlay used to highlight the line `binky-jump' to.")

(defvar binky-debug-buffer "*Binky Debug*"
  "Buffer used to debug.")

;;; Functions

;; (defun binky--message (mark)
;;   "docstring"
;;   (error "")
;;   )

(defun binky--log (&rest args)
  "Print log into `binky-debug-buffer' about ARGS.
ARGS format is as same as `format' command."
  (with-current-buffer (get-buffer-create binky-debug-buffer t)
    (goto-char (point-max))
    (insert "\n")
    (insert (apply #'format args))))

(defun binky--regexp-match (lst)
  "Return non-nil if current buffer name match the LST."
  (and lst (string-match-p
            (mapconcat (lambda (x) (concat "\\(?:" x "\\)")) lst "\\|")
            (buffer-name))))

(defun binky--exclude-regexp-p ()
  "Return non-nil if current buffer name should be exclude."
  (and (not (binky--regexp-match binky-include-regexps))
       (binky--regexp-match binky-exclude-regexps)))

(defun binky--exclude-mode-p ()
  "Return non-nil if current buffer major mode should be exclude."
  (and binky-exclude-modes
       (memq mode-name binky-exclude-modes)))

(defun binky--frequency-increase ()
  "Frequency increases by 1 in after each idle."
  (cl-incf binky-frequency 1))

(defun binky--frequency-get (marker)
  "Return value of `binky-frequency' of buffer which MARKER points to."
  (or (buffer-local-value 'binky-frequency (marker-buffer marker)) 0))

(defun binky--record-get-info (record)
  "Return a list (name position mode context) of information from RECORD."
  (let ((marker (cdr record)))
    (with-current-buffer (marker-buffer marker)
      (list (or buffer-file-name (buffer-name) "")
            (marker-position marker)
            major-mode
            (save-excursion
              (goto-char marker)
              (buffer-substring (pos-bol) (pos-eol)))))))

(defun binky-record-auto-update ()
  "Update `binky-auto-alist' and `binky-back-record' automatically."
  ;; delete back-record if buffer not exists
  (when (and binky-back-record
             (null (marker-buffer (cdr binky-back-record))))
    (setq binky-back-record nil))
  ;; update used buffers
  (let* ((marks (remove binky-mark-back binky-mark-auto))
         (len (length marks))
         (result (list))
         (filters (append binky-exclude-functions
                          '(binky--exclude-mode-p
                            binky--exclude-regexp-p))))
    (when (> len 0)
      ;; remove current-buffer
      (cl-dolist (buf (nthcdr 1 (buffer-list)))
        (with-current-buffer buf
          (unless (cl-some #'funcall filters)
            (push (point-marker) result))))
      ;; delete marker duplicated with `binky-alist'
      (setq result (cl-remove-if (lambda (m) (rassoc m binky-alist)) result))
      (cl-case binky-mark-sort-by
        (recency
         (setq result (reverse result)))
        (frequency
         (cl-sort result #'> :key #'binky--frequency-get))
        ;; TODO
        ;; (frecency ())
        ;; (duration ())
        (t nil))
      (setq binky-auto-alist (cl-mapcar (lambda (x y) (cons x y))
                                        marks
                                        result)))))

(defun binky-record-swap-out ()
  "Turn record from marker into list of infos when a buffer is killed."
  (dolist (record binky-alist)
    (let ((info (cdr record)))
	  (when (and (markerp info)
	             (eq (marker-buffer info) (current-buffer)))
        (if buffer-file-name
	        (setcdr record (binky--record-get-info record))
          (delete record binky-alist))))))

(defun binky-record-swap-in ()
  "Turn record from list of infos into marker when a buffer is reopened."
  (dolist (record binky-alist)
    (let ((info (cdr record)))
      (when (and (not (markerp info))
                 (equal (car info) buffer-file-name))
        (setcdr record (set-marker (make-marker) (cadr info)))))))

(defun binky--preview-extract (alist)
  "Return truncated string with selected columns according to ALIST."
  (format " %s\n"
          (mapconcat (lambda (x)
                       (let* ((item (car x))
                              (limit (cdr x))
                              (str (alist-get item alist))
                              (len (length str))
                              (upper (apply #'max
                                            (cl-remove-if-not #'numberp
                                                              (mapcar #'cdr binky-preview-column)))))
                         (when (numberp limit)
                           (setf limit (max limit (length (symbol-name item))))
                           (and (> len limit)
                                (setf (substring str
                                                 (- limit
                                                    (length binky-preview-ellipsis))
                                                 limit)
                                      binky-preview-ellipsis))
                           (setf (substring str len nil) (make-string upper 32)))
                         (substring str 0 limit)))
                     binky-preview-column "  ")))

(defun binky--preview-propertize (record)
  "Return formated string for RECORD in preview."
  (let ((killed (not (markerp (cdr record)))))
    (or killed (setq record (cons (car record) (binky--record-get-info record))))
    (cl-mapcar
     (lambda (x y)
       (let ((column-face (intern (concat "binky-preview-" (symbol-name x))))
             (cond-face (cond
                         (killed 'binky-preview-shadow)
                         ((and (eq x 'mark)
                               (memq (binky--mark-type (string-to-char (substring y -1))) '(auto back)))
                          (intern (concat "binky-preview-mark-"
                                          (symbol-name (binky--mark-type
                                                        (string-to-char (substring y -1)))))))
                         (t nil))))
         (cons x (if (or killed (facep column-face))
                     (propertize y 'face (or cond-face column-face))
                   y))))
     '(mark name position mode context)
     (list (concat "  " (single-key-description (nth 0 record)))
           (file-name-nondirectory (nth 1 record))
           (number-to-string (nth 2 record))
           (string-remove-suffix "-mode" (symbol-name (nth 3 record)))
           (string-trim (nth 4 record))))))

(defun binky--preview-header ()
  "Return formated string of header for preview."
  (binky--preview-extract
   (mapcar (lambda (x)
             (cons (car x)
                   (propertize
                    (symbol-name (car x))
                    'face
                    'binky-preview-header)))
           binky-preview-column)))

(defun binky-preview (&optional force)
  "Display `binky-preview-buffer'.
When there is no window currently showing the buffer or FORCE is non-nil,
popup the window on the bottom."
  ;; TODO show-empty enable
  (let ((total (remove nil
                       (cons binky-back-record
                             (if binky-preview-auto-first
                                 (append binky-auto-alist binky-alist)
                               (append binky-alist binky-auto-alist))))))
    (when (and (or force
                   (not (get-buffer-window binky-preview-buffer)))
               total)
      (with-current-buffer-window
          binky-preview-buffer
          (cons 'display-buffer-in-side-window
                '((window-height . fit-window-to-buffer)
                  (preserve-size . (nil . t))
                  (side . bottom)))
          nil
        (progn
          (setq cursor-in-non-selected-windows nil
                mode-line-format nil
                truncate-lines t)
          ;; insert header if non-nil
          (when (and (consp binky-preview-column)
                     binky-preview-show-header)
            (insert (binky--preview-header)))
          (let* ((final (mapcar #'binky--preview-propertize total))
                 (back (and binky-back-record
                            (binky--preview-propertize binky-back-record)))
                 (dup (and back (rassoc (cdr back) (cdr final)))))
            (when dup
              (setf (cdar dup)
                    (concat (substring (cdar back) -1)
                            (substring (cdar dup) 1))))
            (mapc (lambda (record)
                    (insert (binky--preview-extract record)))
                  (if dup (cdr final) final))))))))

(defun binky--jump-highlight ()
  "Highlight current line in `binky-jump-highlight-duration' seconds."
  (let ((beg (line-beginning-position))
        (end (line-beginning-position 2)))
    (if binky-jump-overlay
        (move-overlay binky-jump-overlay beg end)
      (setq binky-jump-overlay (make-overlay beg end))
      (overlay-put binky-jump-overlay 'face 'binky-jump-highlight)))
  (sit-for binky-jump-highlight-duration)
  (delete-overlay binky-jump-overlay))

(defun binky--mark-type (&optional mark)
  "Return type of MARK or `last-input-event'."
  (let ((char (or mark last-input-event)))
    (cond
     ((memq char '(?\C-g ?\C-\[ escape)) 'quit)
     ((memq char (cons help-char help-event-list)) 'help)
     ((equal char binky-mark-back) 'back)
     ((memq char binky-mark-auto) 'auto)
     ((and (characterp char) (<= 33 char 126)) 'mannual)
     (t nil))))

(defun binky--mark-exist (mark)
  "Return non-nil if MARK already exists in both alists."
  (or (alist-get mark (list binky-back-record))
      (alist-get mark binky-alist)
      (alist-get mark binky-auto-alist)))

(defun binky--mark-add (mark)
  "Add (MARK . MARKER) into `binky-alist'."
  (cond
   ((not (eq (binky--mark-type mark) 'mannual))
    (message "%s not allowed." mark))
   ((eq major-mode 'xwidget-webkit-mode)
    (message "%s not allowed" major-mode))
   ((and (binky--mark-exist mark) (not binky-mark-overwrite))
    (message "Mark %s exists." mark))
   ((rassoc (point-marker) binky-alist)
    (message "Record exists." ))
   (t (setf (alist-get mark binky-alist) (point-marker)))))

(defun binky--mark-delete (mark)
  "Delete (MARK . INFO) from `binky-alist'."
  (if (and (binky--mark-exist mark)
           (eq (binky--mark-type mark) 'mannual))
      (setq binky-alist (assoc-delete-all mark binky-alist))
    (message "%s is not allowed." mark)))

(defun binky--mark-jump (mark)
  "Jump to point according to (MARK . INFO) in both alists."
  (if-let ((info (binky--mark-exist mark)))
      (progn
        (if (characterp binky-mark-back)
            (setq binky-back-record (cons binky-mark-back (point-marker)))
          (setq binky-back-record nil))
        (if (markerp info)
            (progn
              (switch-to-buffer (marker-buffer info))
              (goto-char info))
          (find-file (car info)))
        (when (and (numberp binky-jump-highlight-duration)
                   (> binky-jump-highlight-duration 0))
          (binky--jump-highlight)))
    (message "No marks %s" mark)))

(defun binky-mark-read (prompt)
  "Read and return a MARK possibly showing existing records.
Prompt with the string PROMPT.  If `binky-alist', `binky-auto-alist' and
`binky-preview-delay' are both non-nil, display a window listing exisiting
marks after `binky-preview-delay' seconds.  If `help-char' (or a member of
`help-event-list') is pressed, display such a window regardless.   Press
\\[keyboard-quit] to quit."
  (let ((timer (when (numberp binky-preview-delay)
		         (run-with-timer binky-preview-delay nil #'binky-preview))))
    (unwind-protect
        (progn
          (while (or (eq (binky--mark-type
                          (read-key (propertize prompt 'face 'minibuffer-prompt)))
                         'help))
            (binky-preview))
          (when (eq (binky--mark-type) 'quit)
            (keyboard-quit))
          (if (memq (binky--mark-type) '(auto back mannual))
              last-input-event
            (message "Non-character input-event")))
      (and (timerp timer) (cancel-timer timer))
      (let* ((buf binky-preview-buffer)
             (win (get-buffer-window buf)))
        (and (window-live-p win) (delete-window win))
        (and (get-buffer buf) (kill-buffer buf))))))

;;; Commands

;;;###autoload
(defun binky-add (mark)
  "Add the record in current point with MARK."
  (interactive (list (binky-mark-read "Mark add: ")))
  (binky--mark-add mark))

;;;###autoload
(defun binky-delete (mark)
  "Delete the record according to MARK."
  (interactive (list (binky-mark-read "Mark delete: ")))
  (binky--mark-delete mark))

;;;###autoload
(defun binky-jump (mark)
  "Jump to point according to record of MARK."
  (interactive (list (binky-mark-read "Mark jump: ")))
  (binky--mark-jump mark))

;;;###autoload
(defun binky-binky (mark)
  "Command to add, delete or jump with MARK.
If MARK is exists, then call `binky-jump'.
If MARK doesn't existsk, then call `binky-add'.
;; TODO If MARK is Upercase, and the lowercase exists, then call `binky-delete'."
  (interactive (list (binky-mark-read "Mark: ")))
  (if (binky--mark-exist mark)
      (binky--mark-jump mark)
    (and (eq (binky--mark-type mark) 'mannual)
         (binky--mark-add mark))))

(define-minor-mode binky-mode
  "Toggle `binky-mode'.
This global minor mode allows you to easily jump between buffers
you used ever."
  :group 'binky
  :global t
  :require 'binky-mode
  (if binky-mode
      (progn
        (add-hook 'buffer-list-update-hook 'binky-record-auto-update)
        (add-hook 'kill-buffer-hook 'binky-record-swap-out)
        (add-hook 'find-file-hook 'binky-record-swap-in)
        (setq binky-frequency-timer
              (run-with-idle-timer binky-frequency-idle
                                   t #'binky--frequency-increase)))
    (remove-hook 'buffer-list-update-hook 'binky-record-auto-update)
    (remove-hook 'kill-buffer-hook 'binky-record-swap-out)
    (remove-hook 'find-file-hook 'binky-record-swap-in)
    (cancel-timer binky-frequency-timer)
    (setq binky-frequency-timer nil)))

(provide 'binky-mode)
;;; binky-mode.el ends here
