;;; slack-team.el ---  team class                    -*- lexical-binding: t; -*-

;; Copyright (C) 2016  南優也

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
(require 'eieio)

(defvar slack-teams nil)
(defvar slack-current-team nil)
(defcustom slack-prefer-current-team nil
  "If set to t, using `slack-current-team' for interactive function.
use `slack-change-current-team' to change `slack-current-team'"
  :group 'slack)

(defclass slack-team ()
  ((id :initarg :id)
   (token :initarg :token :initform nil)
   (client-id :initarg :client-id)
   (client-secret :initarg :client-secret)
   (name :initarg :name :initform nil)
   (domain :initarg :domain)
   (self :initarg :self)
   (self-id :initarg :self-id)
   (self-name :initarg :self-name)
   (channels :initarg :channels)
   (groups :initarg :groups)
   (ims :initarg :ims)
   (file-room :initform nil)
   (users :initarg :users)
   (bots :initarg :bots)
   (ws-url :initarg :ws-url)
   (ws-conn :initarg :ws-conn :initform nil)
   (ping-timer :initform nil)
   (check-ping-timeout-timer :initform nil)
   (check-ping-timeout-sec :initarg :check-ping-timeout-sec
                           :initform 20)
   (reconnect-auto :initarg :reconnect-auto :initform t)
   (reconnect-timer :initform nil)
   (reconnect-after-sec :initform 1)
   (reconnect-after-sec-max :initform 4096)
   (last-pong :initform nil)
   (waiting-send :initform nil)
   (sent-message :initform (make-hash-table))
   (message-id :initform 0)
   (connected :initform nil)
   (subscribed-channels :initarg :subscribed-channels :type list)))

(defun slack-team-find (id)
  (cl-find-if #'(lambda (team) (string= id (oref team id)))
              slack-teams))

(defmethod slack-team-disconnect ((team slack-team))
  (slack-ws-close team))

(defmethod slack-team-equalp ((team slack-team) other)
  (with-slots (client-id) team
    (string= client-id (oref other client-id))))

(defmethod slack-team-name ((team slack-team))
  (oref team name))

(defun slack-register-team (&rest plist)
  (cl-labels ((same-client-id
               (client-id)
               (cl-find-if #'(lambda (team)
                               (string= client-id (oref team client-id)))
                           slack-teams))
              (missing (plist)
                       (cl-remove-if
                        #'null
                        (mapcar #'(lambda (key)
                                    (unless (plist-member plist key)
                                      key))
                                '(:name :client-id :client-secret)))))
    (let ((missing (missing plist)))
      (if missing
          (error "Missing Keyword: %s" missing)))
    (let ((team (apply #'slack-team (slack-collect-slots 'slack-team plist))))
      (mapcan #'(lambda (other) (if (slack-team-equalp team other)
                                    (progn
                                      (slack-team-disconnect other)
                                      (slack-start team))))
              slack-teams)
      (setq slack-teams
            (cl-remove-if #'(lambda (other) (slack-team-equalp team other))
                          slack-teams))
      (push team slack-teams))))

(defun slack-team-find-by-name (name)
  (if name
      (cl-find-if #'(lambda (team) (string= name (oref team name)))
                  slack-teams)))

(defun slack-team-select ()
  (cl-labels ((select-team ()
                           (slack-team-find-by-name
                            (completing-read
                             "Select Team: "
                             (mapcar #'(lambda (team) (oref team name))
                                     (slack-team-connected-list))))))
    (let ((team (if (and slack-prefer-current-team
                         slack-current-team)
                    slack-current-team
                  (select-team))))
      (if (and slack-prefer-current-team
               (not slack-current-team))
          (if (yes-or-no-p (format "Set %s to current-team?"
                                   (oref team name)))
              (setq slack-current-team team)))
      team)))

(defmethod slack-team-connectedp ((team slack-team))
  (oref team connected))

(defun slack-team-connected-list ()
  (cl-remove-if #'null
                (mapcar #'(lambda (team)
                            (if (slack-team-connectedp team) team))
                        slack-teams)))

(defun slack-set-current-team ()
  (interactive)
  (let ((team (slack-team-find-by-name
               (completing-read
                "Select Team: "
                (mapcar #'(lambda (team) (oref team name))
                        slack-teams)))))
    (setq slack-current-team team)
    (message "Set slack-current-team to %s" (or (and team (oref team name))
                                                "nil"))
    (if team
        (slack-team-connect team))))

(defmethod slack-team-connect ((team slack-team))
  (unless (slack-team-connectedp team)
    (slack-start team)))

(provide 'slack-team)
;;; slack-team.el ends here
