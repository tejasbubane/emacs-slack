;;; slack-reply.el ---handle reply from slack        -*- lexical-binding: t; -*-

;; Copyright (C) 2015  yuya.minami

;; Author: yuya.minami <yuya.minami@yuyaminami-no-MacBook-Pro.local>
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
(require 'eieio)
(require 'slack-message)

(defmethod slack-message-handle-reply ((m slack-reply))
  (with-slots (reply-to) m
    (let ((sent-msg (slack-message-find-sent m)))
      (if sent-msg
          (progn
            (oset sent-msg ts (oref m ts))
            (slack-message-update sent-msg))))))

(defmethod slack-message-find-sent ((m slack-reply))
  (cl-labels
      ((find (reply-to)
             (cl-find-if #'(lambda (msg) (eq reply-to (oref msg id)))
                         slack-sent-message)))
    (with-slots (reply-to) m
      (let ((found (gethash reply-to slack-sent-message)))
        (remhash reply-to slack-sent-message)
        found))))

(defmethod slack-message-sender-equalp ((m slack-reply) sender-id)
  (string= (oref m user) sender-id))


(provide 'slack-reply)
;;; slack-reply.el ends here
