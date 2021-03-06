;;; slack-message-editor.el ---  edit message interface  -*- lexical-binding: t; -*-

;; Copyright (C) 2015  南優也

;; Author: 南優也 <yuyaminami@minamiyuunari-no-MacBook-Pro.local>
;; Keywords:

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;;

;;; Code:
(require 'slack-message-sender)

(defconst slack-message-edit-url "https://slack.com/api/chat.update")
(defconst slack-message-edit-buffer-name "*Slack - Edit message*")
(defconst slack-message-write-buffer-name "*Slack - Write message*")
(defvar slack-buffer-function)
(defvar slack-my-user-id)
(defvar slack-token)
(defvar slack-target-ts)
(make-local-variable 'slack-target-ts)
(defvar slack-message-edit-buffer-type)
(make-local-variable 'slack-message-edit-buffer-type)
(defvar slack-current-room)
(make-local-variable 'slack-current-room)

(defvar slack-edit-message-mode-map
  (let ((keymap (make-sparse-keymap)))
    (define-key keymap (kbd "C-s C-m") #'slack-message-embed-mention)
    (define-key keymap (kbd "C-s C-c") #'slack-message-embed-channel)
    (define-key keymap (kbd "C-c C-k") #'slack-message-cancel-edit)
    (define-key keymap (kbd "C-c C-c") #'slack-message-send-edited)
    keymap))

(define-derived-mode slack-edit-message-mode fundamental-mode "Slack Edit Msg"
  ""
  (slack-buffer-enable-emojify))


(defun slack-message-write-another-buffer ()
  (interactive)
  (let ((target-room (if (boundp 'slack-current-room) slack-current-room
                       (slack-message-read-room)))
        (buf (get-buffer-create slack-message-write-buffer-name)))
    (with-current-buffer buf
      (slack-message-setup-edit-buf target-room 'new))
    (funcall slack-buffer-function buf)))

(defun slack-message-edit ()
  (interactive)
  (let* ((target (thing-at-point 'word))
         (ts (get-text-property 0 'ts target))
         (msg (slack-room-find-message slack-current-room ts)))
    (unless msg
      (error "Can't find original message"))
    (unless (string= slack-my-user-id (oref msg user))
      (error "Cant't edit other user's message"))
    (slack-message-edit-text msg slack-current-room)))

(defun slack-message-edit-text (msg room)
  (let ((buf (get-buffer-create slack-message-edit-buffer-name)))
    (with-current-buffer buf
      (slack-edit-message-mode)
      (slack-message-setup-edit-buf room 'edit :ts (oref msg ts))
      (insert (oref msg text)))
    (funcall slack-buffer-function buf)))

(cl-defun slack-message-setup-edit-buf (room buf-type &key ts)
  (slack-edit-message-mode)
  (setq buffer-read-only nil)
  (erase-buffer)
  (if (and (eq buf-type 'edit) ts)
      (set (make-local-variable 'slack-target-ts) ts))
  (set (make-local-variable 'slack-message-edit-buffer-type) buf-type)
  (slack-buffer-set-current-room room)
  (message "C-c C-c to send edited msg"))

(defun slack-message-cancel-edit ()
  (interactive)
  (let ((room slack-current-room))
    (erase-buffer)
    (delete-window)
    (slack-room-make-buffer-with-room room)))

(defun slack-message-send-edited ()
  (interactive)
  (let ((buf-string (buffer-substring (point-min) (point-max)))
        (room slack-current-room))
    (cl-case slack-message-edit-buffer-type
      ('edit (slack-message--edit (oref room id)
                                  slack-target-ts
                                  buf-string))
      ('new (slack-message--send buf-string)))
    (delete-window)))

(defun slack-message--edit (channel ts text)
  (cl-labels ((on-edit (&key data &allow-other-keys)
                       (slack-request-handle-error
                        (data "slack-message--edit"))))
    (slack-request
     slack-message-edit-url
     :type "POST"
     :sync nil
     :params (list (cons "token" slack-token)
                   (cons "channel" channel)
                   (cons "ts" ts)
                   (cons "text" text))
     :success #'on-edit)))

(provide 'slack-message-editor)
;;; slack-message-editor.el ends here
