;;; package --- Summary
;;; Commentary:

;;; Code:

(require 'eieio)
(require 'slack-message-formatter)
(require 'slack-message-reaction)
(require 'slack-message-editor)

(defvar slack-user-message-keymap
  (let ((keymap (make-sparse-keymap)))
    keymap))

(defmethod slack-message-sender-equalp ((m slack-user-message) sender-id)
  (string= (oref m user) sender-id))

(defmethod slack-message-header ((m slack-user-message))
  (with-slots (ts edited-at) m
    (let* ((name (slack-message-sender-name m))
           (time (slack-message-time-to-string ts))
           (edited-at (slack-message-time-to-string edited-at))
           (header (format "%s" name)))
      (if edited-at
          (format "%s edited_at: %s" header edited-at)
        header))))

(defmethod slack-message-propertize ((m slack-user-message) text)
  (put-text-property 0 (length text) 'keymap slack-user-message-keymap text)
  text)

(provide 'slack-user-message)
;;; slack-user-message.el ends here
