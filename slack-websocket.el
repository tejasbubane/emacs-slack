;;; slack-websocket.el --- slack websocket interface  -*- lexical-binding: t; -*-

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
(require 'websocket)
(require 'slack-request)
(require 'slack-message)
(require 'slack-reply)

(defun slack-ws-open (team)
  (with-slots (ws-url ws-conn) team
    (unless ws-conn
      (setq ws-conn
            (websocket-open
             ws-url
             :on-message
             #'(lambda (websocket frame)
                 (slack-ws-on-message websocket frame team)))))))

(defun slack-ws-close (&optional team)
  (interactive)
  (unless team
    (setq team (slack-team-select)))
  (with-slots (connected ws-conn last-pong) team
    (if ws-conn
        (progn
          (websocket-close ws-conn)
          (setq ws-conn nil)
          (setq connected nil)
          (slack-ws-cancel-ping-timer team)
          (slack-ws-cancel-check-ping-timeout-timer team)
          (slack-ws-cancel-reconnect-timer team)
          (message "Slack Websocket Closed"))
      (message "Slack Websocket is not open"))))

(defun slack-ws-send (payload team)
  (cl-labels ((restart (team)
                       (message "Slack Websocket is Closed. Try to Reconnect")
                       (slack-start team)))
    (with-slots (waiting-send ws-conn) team
      (push payload waiting-send)
      (if (websocket-openp ws-conn)
          (condition-case _e
              (progn
                (websocket-send-text ws-conn payload)
                (setq waiting-send
                      (cl-remove-if #'(lambda (p) (string= payload p))
                                    waiting-send)))
            ('websocket-closed (restart team)))
        (restart team)))))

(defun slack-ws-resend (team)
  (with-slots (waiting-send) team
    (setq waiting-send nil)
    (mapcar #'(lambda (m) (slack-ws-send m team)
                (sleep-for 1))
            waiting-send)))

(defun slack-ws-recursive-decode (payload)
  (cl-labels ((decode (e) (if (stringp e)
                              (decode-coding-string e 'utf-8-unix)
                            e))
              (recur (payload acc)
                     (if (and payload (< 0 (length payload)))
                         (let ((h (car payload)))
                           (if (and (not (stringp h)) (or (arrayp h) (listp h)))
                               (recur (cdr payload) (cons (recur (append h nil) ()) acc))
                             (recur (cdr payload) (cons (decode h) acc))))
                       (reverse acc))))
    (recur payload ())))

(defun slack-ws-on-message (_websocket frame team)
  ;; (message "%s" (websocket-frame-payload frame))
  (when (websocket-frame-completep frame)
    (let* ((payload (slack-request-parse-payload
                     (websocket-frame-payload frame)))
           (decoded-payload (slack-ws-recursive-decode payload))
           (type (plist-get decoded-payload :type)))
      ;; (message "%s" decoded-payload)
      (cond
       ((string= type "pong")
        (slack-ws-handle-pong decoded-payload team))
       ((string= type "hello")
        (slack-ws-cancel-reconnect-timer team)
        (slack-ws-set-ping-timer team)
        (slack-ws-set-check-ping-timer team)
        (slack-ws-resend team)
        (message "Slack Websocket Is Ready!"))
       ((plist-get decoded-payload :reply_to)
        (slack-ws-handle-reply decoded-payload team))
       ((string= type "message")
        (slack-ws-handle-message decoded-payload team))
       ((string= type "reaction_added")
        (slack-ws-handle-reaction-added decoded-payload team))
       ((string= type "reaction_removed")
        (slack-ws-handle-reaction-removed decoded-payload team))
       ((string= type "channel_created")
        (slack-ws-handle-channel-created decoded-payload team))
       ((or (string= type "channel_archive")
            (string= type "group_archive"))
        (slack-ws-handle-room-archive decoded-payload team))
       ((or (string= type "channel_unarchive")
            (string= type "group_unarchive"))
        (slack-ws-handle-room-unarchive decoded-payload team))
       ((string= type "channel_deleted")
        (slack-ws-handle-channel-deleted decoded-payload team))
       ((or (string= type "channel_rename")
            (string= type "group_rename"))
        (slack-ws-handle-room-rename decoded-payload team))
       ((or (string= type "channel_joined")
            (string= type "group_joined"))
        (slack-ws-handle-room-joined decoded-payload team))
       ((string= type "presence_change")
        (slack-ws-handle-presence-change decoded-payload team))
       ((or (string= type "bot_added")
            (string= type "bot_changed"))
        (slack-ws-handle-bot decoded-payload) team)
       ((string= type "file_shared")
        (slack-ws-handle-file-shared decoded-payload team))
       ((or (string= type "file_deleted")
            (string= type "file_unshared"))
        (slack-ws-handle-file-deleted decoded-payload team))))))

(defun slack-ws-handle-message (payload team)
  (let ((m (slack-message-create payload :team team)))
    (when m
      (slack-message-update m team))))

(defun slack-ws-handle-reply (payload team)
  (let ((ok (plist-get payload :ok)))
    (if (eq ok :json-false)
        (let ((err (plist-get payload :error)))
          (message "Error code: %s msg: %s"
                   (plist-get err :code)
                   (plist-get err :msg)))
      (let ((message-id (plist-get payload :reply_to)))
        (if (integerp message-id)
            (slack-message-handle-reply
             (slack-message-create payload)
             team))))))

(cl-defmacro slack-ws-handle-reaction ((payload team) &body body)
  `(let* ((item (plist-get ,payload :item))
          (room (slack-room-find (plist-get item :channel)
                                 ,team)))
     (if room
         (let ((msg (slack-room-find-message room (plist-get item :ts))))
           (if msg
               (let* ((r-name (plist-get ,payload :reaction))
                      (r-count 1)
                      (r-users (list (plist-get ,payload :user)))
                      (reaction (make-instance 'slack-reaction
                                               :name r-name
                                               :count r-count
                                               :users r-users)))

                 ,@body
                 (slack-message-update msg ,team t t)))))))

(defun slack-ws-handle-reaction-added (payload team)
  (slack-ws-handle-reaction
   (payload team)
   (slack-message-append-reaction msg reaction)
   (slack-reaction-notify payload team)))

(defun slack-ws-handle-reaction-removed (payload team)
  (slack-ws-handle-reaction
   (payload team)
   (slack-message-pop-reaction msg reaction)))

(defun slack-ws-handle-channel-created (payload team)
  ;; (let ((id (plist-get (plist-get payload :channel) :id)))
  ;;   (slack-channel-create-from-info id team))
  )

(defun slack-ws-handle-room-archive (payload team)
  (let* ((id (plist-get payload :channel))
         (room (slack-room-find id team)))
    (oset room is-archived t)
    (message "Channel: %s is archived"
             (slack-room-name room))))

(defun slack-ws-handle-room-unarchive (payload team)
  (let* ((id (plist-get payload :channel))
         (room (slack-room-find id team)))
    (oset room is-archived :json-false)
    (message "Channel: %s is unarchived"
             (slack-room-name room))))

(defun slack-ws-handle-channel-deleted (payload team)
  (let ((id (plist-get payload :channel)))
    (slack-room-deleted id team)))

(defun slack-ws-handle-room-rename (payload team)
  (let* ((c (plist-get payload :channel))
         (room (slack-room-find (plist-get c :id) team))
         (old-name (slack-room-name room))
         (new-name (plist-get c :name)))
    (oset room name new-name)
    (message "Renamed channel from %s to %s"
             old-name
             new-name)))

(defun slack-ws-handle-room-joined (payload team)
  (cl-labels
      ((replace-room (room rooms)
                     (cons room (cl-delete-if
                                 #'(lambda (r)
                                     (slack-room-equal-p room r))
                                 rooms))))
    (let* ((c (plist-get payload :channel)))
      (if (plist-get c :is_channel)
          (let ((channel (slack-channel-create c)))
            (with-slots (channels) team
              (setq channels
                    (replace-room channel channels)))
            (message "Joined channel %s"
                     (slack-room-name channel)))
        (let ((group (slack-group-create c)))
          (with-slots (groups) team
            (setq groups
                  (replace-room group groups)))
          (message "Joined group %s"
                   (slack-room-name group)))))))

(defun slack-ws-handle-presence-change (payload team)
  (let* ((id (plist-get payload :user))
         (user (slack-user-find id team))
         (presence (plist-get payload :presence)))
    (plist-put user :presence presence)))

(defun slack-ws-handle-bot (payload team)
  (let ((bot (plist-get payload :bot)))
    (with-slots (bots) team
      (push bot bots))))

(defun slack-ws-handle-file-shared (payload team)
  (let ((file (slack-file-create (plist-get payload :file))))
    (slack-file-pushnew file team)))

(defun slack-ws-handle-file-deleted (payload team)
  (let ((file-id (plist-get payload :file_id))
        (room (slack-file-room-obj team)))
    (with-slots (messages last-read) room
      (setq messages (cl-remove-if #'(lambda (f)
                                       (string= file-id (oref f id)))
                                   messages)))))
(defun slack-log-time ()
  (format-time-string "%Y-%m-%d %H:%M:%S"))

(defun slack-ws-set-ping-timer (team)
  (with-slots (ping-timer) team
    (unless ping-timer
      (setq ping-timer
            (run-at-time t 10 #'(lambda () (slack-ws-ping team)))))))

(defun slack-ws-ping (team)
  (with-slots (message-id) team
    (cl-incf message-id)
    (let* ((m (list :id message-id
                    :type "ping"
                    :time (format-time-string "%s")))
           (json (json-encode m)))
      (slack-ws-send json team))))

(defun slack-ws-set-check-ping-timer (team)
  (with-slots
      (check-ping-timeout-timer check-ping-timeout-sec) team
    (unless check-ping-timeout-timer
      (setq check-ping-timeout-timer
            (run-at-time t check-ping-timeout-sec
                         #'(lambda () (slack-ws-check-ping-timeout team)))))))

(defun slack-ws-check-ping-timeout (team)
  (with-slots (last-pong) team
    (if last-pong
        (let* ((current (time-to-seconds (current-time)))
               (since-last-pong (- current last-pong)))
          (when (> since-last-pong 20)
            (slack-ws-ping-timeout team))))))

(defun slack-ws-ping-timeout (team)
  (slack-ws-cancel-check-ping-timeout-timer team)
  (message "Slack Websocket PING Timeout.")
  (slack-ws-close team)
  (slack-ws-cancel-ping-timer team)
  (if (oref team reconnect-auto)
      (with-slots (reconnect-timer) team
        (setq reconnect-timer
              (run-at-time "1 sec" nil
                           #'(lambda () (slack-ws-reconnect team)))))))

(defun slack-ws-cancel-check-ping-timeout-timer (team)
  (with-slots (check-ping-timeout-timer last-pong) team
    (if (timerp check-ping-timeout-timer)
        (cancel-timer check-ping-timeout-timer))
    (setq check-ping-timeout-timer nil)
    (setq last-pong nil)))

(defun slack-ws-cancel-ping-timer (team)
  (with-slots (ping-timer) team
    (if (timerp ping-timer)
        (cancel-timer ping-timer))
    (setq ping-timer nil)))

(defun slack-ws-reconnect (team)
  (message "Slack Websocket Try To Reconnect")
  (with-slots
      ((last-reconnect reconnect-after-sec)
       (reconnect-max reconnect-after-sec-max)) team
    (let* ((after (if (> last-reconnect reconnect-max)
                      1
                    (* last-reconnect 2))))
      (setq last-reconnect after)
      (slack-ws-close team)
      (slack-authorize
       team
       (cl-function
        (lambda
          (&key error-thrown &allow-other-keys)
          (message "Slack Reconnect Error: %s" error-thrown)
          (oset team reconnect-timer
                (run-at-time after nil
                             #'(lambda () (slack-ws-reconnect team))))))))))

(defun slack-ws-cancel-reconnect-timer (team)
  (with-slots (reconnect-timer reconnect-after-sec) team
    (if (timerp reconnect-timer)
        (cancel-timer reconnect-timer))
    (setq reconnect-timer nil)
    (setq reconnect-after-sec 1)))

(defun slack-ws-handle-pong (_payload team)
  (with-slots (last-pong) team
    (setq last-pong (time-to-seconds (current-time)))))

(provide 'slack-websocket)
;;; slack-websocket.el ends here
