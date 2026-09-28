;;; init.el --- Seli Emacs config -*- lexical-binding: t; -*-

;;; Commentary:
;; Org とプログラミングの両方に使う構成。組み込みの Eglot / Flymake と
;; Apheleia を中心に、外部の LSP・フォーマッタを利用する。

;;; Package bootstrap

(require 'package)

;; Keep third-party byte/native compilation noise out of the startup UI.
(setq native-comp-async-report-warnings-errors 'silent
      byte-compile-warnings '(not obsolete free-vars unresolved noruntime lexical make-local)
      warning-suppress-types '((bytecomp) (comp) (native-compiler))
      warning-suppress-log-types '((bytecomp) (comp) (native-compiler)))

(add-to-list 'display-buffer-alist
             '("\\`\\*Warnings\\*\\'" . (display-buffer-no-window)))
(add-to-list 'display-buffer-alist
             '("\\`\\*Compile-Log\\*\\'" . (display-buffer-no-window)))

(defconst seli/opaque-ui-background "#fffaf3")
(defconst seli/opaque-ui-background-active "#f2e9e1")
(defconst seli/active-line-indicator "#dfdad9")
(defconst seli/buffer-alpha-background
  (if (getenv "EMACS_SCRATCHPAD") 100 100)
  "Frame background opacity; opaque in the scratchpad to avoid a GDK shm crash.")

(defconst seli/instance-subdir
  (if (getenv "EMACS_SCRATCHPAD") "scratchpad/" "")
  "Per-daemon state directory beneath the Emacs XDG directories.")

(when (getenv "EMACS_SCRATCHPAD")
  (setq frame-title-format "Scratchpad Emacs"))

(defconst seli/cache-dir
  (expand-file-name (concat "emacs/" seli/instance-subdir)
                    (or (getenv "XDG_CACHE_HOME") "~/.cache/")))

(defconst seli/state-dir
  (expand-file-name (concat "emacs/" seli/instance-subdir)
                    (or (getenv "XDG_STATE_HOME") "~/.local/state/")))

(defconst seli/data-dir
  (expand-file-name "emacs/" (or (getenv "XDG_DATA_HOME") "~/.local/share/")))

(defconst seli/config-dir
  (file-name-directory (or load-file-name buffer-file-name)))

(dolist (dir (list seli/cache-dir seli/state-dir seli/data-dir))
  (unless (file-directory-p dir)
    (make-directory dir t)))

(setq package-archives
      '(("gnu" . "https://elpa.gnu.org/packages/")
        ("nongnu" . "https://elpa.nongnu.org/nongnu/")
        ("melpa" . "https://melpa.org/packages/")))

(setq package-user-dir (expand-file-name "elpa" seli/data-dir))
(package-initialize)

(defconst seli/package-archive-max-age (* 3 24 60 60)
  "Maximum age of a cached package archive before refreshing it.")

(defun seli/package-archives-fresh-p ()
  "Return non-nil if all cached package archives are fresh."
  (and package-archive-contents
       (catch 'stale
         (dolist (archive package-archives)
           (let* ((name (car archive))
                  (file (expand-file-name
                         (format "archives/%s/archive-contents" name)
                         package-user-dir)))
             (when (or (not (file-exists-p file))
                       (> (float-time (time-subtract
                                       (current-time)
                                       (file-attribute-modification-time
                                        (file-attributes file))))
                          seli/package-archive-max-age))
               (throw 'stale nil))))
         t)))

(unless (seli/package-archives-fresh-p)
  (package-refresh-contents))

(unless (package-installed-p 'use-package)
  (package-install 'use-package))

(require 'use-package)
(setq use-package-always-ensure t
      use-package-always-defer t
      use-package-expand-minimally t)

(use-package autothemer :ensure t)

;; Rose Pine Dawn is vendored with this configuration, so keep package
;; management exclusively on package.el and load the local theme directly.
(add-to-list 'custom-theme-load-path (expand-file-name "themes/" seli/config-dir))

;;; Evil must see these before any Evil-related package is loaded.

(setq evil-want-keybinding nil
      evil-want-C-u-scroll t
      evil-want-C-i-jump nil
      evil-undo-system 'undo-redo
      evil-respect-visual-line-mode nil
      evil-default-cursor 'box
      evil-normal-state-cursor 'box
      evil-emacs-state-cursor 'box
      evil-visual-state-cursor 'box
      evil-insert-state-cursor 'bar
      evil-replace-state-cursor 'bar
      evil-operator-state-cursor 'hbar
      evil-motion-state-cursor 'box)

(defconst seli/terminal-cursor-shapes
  '((box . "\e[2 q")
    (bar . "\e[6 q")
    (hbar . "\e[4 q"))
  "DECSCUSR cursor shape escape sequences for terminal Emacs.")

(defun seli/set-cursor-shape (shape)
  "Set cursor SHAPE in GUI and terminal frames."
  (setq-default cursor-type shape)
  (setq cursor-type shape)
  (unless (display-graphic-p)
    (let ((sequence (alist-get shape seli/terminal-cursor-shapes)))
      (when sequence
        (send-string-to-terminal sequence)))))

(defun seli/apply-evil-cursor-shape ()
  "Apply cursor shape for the current Evil state."
  (seli/set-cursor-shape
   (pcase (and (boundp 'evil-state) evil-state)
     ('insert 'bar)
     ('replace 'bar)
     ('operator 'hbar)
     ('normal 'box)
     ('visual 'box)
     ('motion 'box)
     ('emacs 'box)
     (_ 'box))))

;;; Files, backups, and XDG-friendly state

(setq backup-directory-alist `(("." . ,(expand-file-name "backup/" seli/cache-dir)))
      auto-save-file-name-transforms `((".*" ,(expand-file-name "auto-save/" seli/cache-dir) t))
      auto-save-list-file-prefix (expand-file-name "auto-save-list/.saves-" seli/cache-dir)
      create-lockfiles nil
      custom-file (expand-file-name "custom.el" seli/state-dir)
      recentf-save-file (expand-file-name "recentf" seli/state-dir)
      savehist-file (expand-file-name "savehist" seli/state-dir)
      bookmark-default-file (expand-file-name "bookmarks" seli/state-dir))

(dolist (dir (list (expand-file-name "backup/" seli/cache-dir)
                   (expand-file-name "auto-save/" seli/cache-dir)
                   (expand-file-name "auto-save-list/" seli/cache-dir)))
  (unless (file-directory-p dir)
    (make-directory dir t)))

;;; Core editor behavior

(setq inhibit-startup-screen t
      ring-bell-function #'ignore
      visible-bell nil
      use-short-answers t
      confirm-kill-processes nil
      sentence-end-double-space nil
      require-final-newline t
      scroll-margin 3
      scroll-conservatively 101
      scroll-preserve-screen-position t
      scroll-step 1
      auto-window-vscroll nil
      fast-but-imprecise-scrolling t
      next-screen-context-lines 3
      tab-width 2
      standard-indent 2
      fill-column 100
      indent-tabs-mode nil)

(setq-default tab-width 2
              indent-tabs-mode nil
              truncate-lines nil)

(setq display-line-numbers-type 'relative)
(global-display-line-numbers-mode 1)

(set-language-environment "UTF-8")
(prefer-coding-system 'utf-8)

(global-display-line-numbers-mode 1)
(setq display-line-numbers-type 'relative)
(global-hl-line-mode 1)
(column-number-mode 1)
(size-indication-mode 1)
(show-paren-mode 1)
(global-auto-revert-mode 1)
(delete-selection-mode 1)
(savehist-mode 1)
(recentf-mode 1)
(winner-mode 1)

(setq auto-revert-verbose nil
      global-auto-revert-non-file-buffers t)

(setq-default show-trailing-whitespace nil)

;; `yank' normally prefers Emacs's kill ring.  Use the desktop clipboard first
;; so text copied in another Wayland application can be pasted with C-y; it
;; still falls back to the latest killed text when no clipboard is available.
(global-set-key (kbd "C-y") #'clipboard-yank)
(global-set-key (kbd "C-S-v") #'clipboard-yank)

(defun seli/save-all-buffers ()
  "Save modified file buffers without prompting."
  (save-some-buffers t))

(add-hook 'focus-out-hook #'seli/save-all-buffers)

(defface seli-dangerous-char
  '((t (:background "red" :foreground "white" :weight bold)))
  "Face for invisible or bidi control characters.")

(font-lock-add-keywords
 nil
 '(("[\u200B\u200C\u200D\uFEFF\u202E\u2066-\u2069]" 0 'seli-dangerous-char prepend)))

;;; UI

(defconst seli/transparent-background-faces
  '(default
    fringe
    line-number
    line-number-current-line
    vertical-border
    internal-border
    hl-line
    fill-column-indicator
    display-fill-column-indicator)
  "Buffer faces that should inherit the transparent frame background.")

(defconst seli/opaque-ui-faces
  '((menu . seli/opaque-ui-background-active)
    (tool-bar . seli/opaque-ui-background-active)
    (tab-bar . seli/opaque-ui-background-active)
    (tab-bar-tab . seli/opaque-ui-background)
    (tab-bar-tab-inactive . seli/opaque-ui-background-active)
    (tab-bar-tab-group-current . seli/opaque-ui-background)
    (tab-bar-tab-group-inactive . seli/opaque-ui-background-active)
    (tab-bar-tab-ungrouped . seli/opaque-ui-background-active)
    (tab-line . seli/opaque-ui-background)
    (tab-line-tab . seli/opaque-ui-background-active)
    (tab-line-tab-current . seli/opaque-ui-background-active)
    (tab-line-tab-inactive . seli/opaque-ui-background)
    (tab-line-highlight . seli/opaque-ui-background-active)
    (tab-line-close-highlight . seli/opaque-ui-background-active)
    (header-line . seli/opaque-ui-background)
    (header-line-highlight . seli/opaque-ui-background-active)
    (mode-line . seli/opaque-ui-background-active)
    (mode-line-active . seli/opaque-ui-background-active)
    (mode-line-inactive . seli/opaque-ui-background)
    (mode-line-highlight . seli/opaque-ui-background-active))
  "UI faces that should stay opaque in GUI frames.")

(defun seli/style-tab-line (&optional frame)
  "Give tabs a flat appearance with a clear selected state in FRAME."
  (dolist (spec '((tab-bar :background "#faf4ed" :foreground "#9893a5"
                           :box nil :height 1.0 :extend t)
                  (tab-bar-tab :background "#f2e9e1" :foreground "#575279"
                               :weight semi-bold :box nil :underline nil)
                  (tab-bar-tab-inactive :background "#faf4ed" :foreground "#9893a5"
                                        :weight normal :box nil :underline nil)
                  (tab-bar-tab-group-current :background "#faf4ed" :foreground "#575279"
                                             :weight semi-bold :box nil)
                  (tab-bar-tab-group-inactive :background "#faf4ed" :foreground "#9893a5"
                                              :weight normal :box nil)
                  (tab-bar-tab-ungrouped :background "#faf4ed" :foreground "#9893a5"
                                         :box nil)
                  (tab-line :background "#faf4ed" :foreground "#9893a5" :box nil :extend t)
                  (tab-line-tab :background "#faf4ed" :foreground "#797593" :box nil)
                  (tab-line-tab-inactive :background "#faf4ed" :foreground "#9893a5" :box nil)
                  (tab-line-tab-current :background "#f2e9e1" :foreground "#575279"
                                        :weight semi-bold :box nil :underline nil)))
    ;; Update the global face as well as FRAME.  This is necessary when Emacs
    ;; starts as a daemon: its initial frame is terminal-only, while the GUI
    ;; frame is created later by emacsclient.
    (apply #'set-face-attribute (car spec) t (cdr spec))
    (apply #'set-face-attribute (car spec) frame (cdr spec))))

(defun seli/apply-frame-appearance (&optional frame)
  "Apply frame appearance settings to FRAME."
  (let ((frame (or frame (selected-frame))))
    (dolist (face seli/transparent-background-faces)
      (when (facep face)
        (set-face-attribute face frame :background 'unspecified)
        (set-face-attribute face t :background 'unspecified)))
    ;; Faces cannot have their own alpha value.  Keep `hl-line' transparent
    ;; and mark the active line without putting an opaque block behind text.
    (set-face-attribute 'hl-line frame
                        :inherit nil
                        :background 'unspecified
                        :underline `(:color ,seli/active-line-indicator
                                           :style line)
                        :extend t)
    (set-face-attribute 'hl-line t
                        :inherit nil
                        :background 'unspecified
                        :underline `(:color ,seli/active-line-indicator
                                           :style line)
                        :extend t)
    (if (display-graphic-p frame)
        (progn
          (set-frame-parameter frame 'alpha '(100 . 100))
          (set-frame-parameter frame 'alpha-background seli/buffer-alpha-background)
          (dolist (entry seli/opaque-ui-faces)
            (let ((face (car entry))
                  (background (symbol-value (cdr entry))))
              (when (facep face)
                (set-face-attribute face frame :background background)
                (set-face-attribute face t :background background))))
          (seli/style-tab-line frame))
      (modify-frame-parameters frame '((background-color . "unspecified-bg"))))))

(defun seli/reapply-frame-appearance (&rest _)
  "Reapply frame appearance after theme changes."
  (dolist (frame (frame-list))
    (seli/apply-frame-appearance frame)))

(add-to-list 'default-frame-alist '(alpha . (100 . 100)))
(add-to-list 'default-frame-alist `(alpha-background . ,seli/buffer-alpha-background))
;; Temporarily disabled to inspect Rose Pine Dawn without local face overrides.
(add-hook 'after-make-frame-functions #'seli/apply-frame-appearance)
(add-hook 'window-setup-hook #'seli/reapply-frame-appearance)
(advice-add 'load-theme :after #'seli/reapply-frame-appearance)
(seli/apply-frame-appearance)

(defconst seli/default-font-family "Monaspace Radon Var")
(defconst seli/default-font-height 120)
(defconst seli/cjk-font-family "Cica")
(defconst seli/icon-font-family "Symbols Nerd Font Mono")

(add-to-list 'default-frame-alist
             `(font . ,(format "%s-%d" seli/default-font-family (/ seli/default-font-height 10))))

(defun seli/apply-fonts (&optional frame)
  "Apply the configured fonts to graphical FRAME.

When Emacs runs as a daemon, its init file has no graphical frame yet.  The
optional FRAME argument lets `after-make-frame-functions' apply the font as
soon as an emacsclient GUI frame is created."
  (let ((frame (or frame (selected-frame))))
    (when (display-graphic-p frame)
      (with-selected-frame frame
        (when (member seli/default-font-family (font-family-list))
          (set-face-attribute 'default frame
                              :family seli/default-font-family
                              :height seli/default-font-height))
        (when (member seli/cjk-font-family (font-family-list))
          (dolist (charset '(kana han cjk-misc))
            (set-fontset-font t charset
                              (font-spec :family seli/cjk-font-family)
                              frame)))
        ;; Nerd Font icons live mostly in Unicode private-use areas.  Append
        ;; the symbols-only font as a fallback so it fills missing glyphs
        ;; without replacing ordinary text, Japanese, or emoji glyphs.
        (when (member seli/icon-font-family (font-family-list))
          (set-fontset-font t 'unicode
                            (font-spec :family seli/icon-font-family)
                            frame 'append))))))

(add-hook 'after-make-frame-functions #'seli/apply-fonts)
(seli/apply-fonts)

(defun seli/tab-line-buffer-name (buffer &optional _buffers)
  "Return a compact tab label for BUFFER."
  (format " %s " (truncate-string-to-width (buffer-name buffer) 24 nil nil "…")))

(setq tab-bar-show t
      tab-bar-close-button-show nil
      tab-bar-new-button-show nil
      tab-bar-separator ""
      tab-line-close-button-show nil
      tab-line-new-button-show nil
      tab-line-separator " "
      tab-line-tab-name-function #'seli/tab-line-buffer-name)

(menu-bar-mode 1)
(when (fboundp 'tool-bar-mode)
  (setq tool-bar-style 'image)
  (tool-bar-mode 1))
(tab-bar-mode 1)
(global-tab-line-mode -1)

;; Load Org's faces before enabling the theme.  Otherwise faces created only
;; when Org loads (notably TODO/DONE) retain Emacs's bright default colors.
(require 'org)
(load-theme 'rose-pine-dawn t)

(defun seli/toggle-theme ()
  "Reload the configured theme."
  (interactive)
  (mapc #'disable-theme custom-enabled-themes)
  (load-theme 'rose-pine-dawn t))

(use-package doom-modeline
  :hook (after-init . doom-modeline-mode)
  :custom
  (doom-modeline-height 22)
  (doom-modeline-buffer-file-name-style 'auto)
  (doom-modeline-icon t))

;; Doom Modeline renders this in its buffer-position segment.  Keep animation
;; disabled: the cat still tracks point through the buffer without a timer
;; continuously redisplaying every frame.
(use-package nyan-mode
  :after doom-modeline
  :demand t
  :custom
  (nyan-bar-length 35)
  (nyan-wavy-trail t)
  (nyan-animate-nyancat nil)
  :config
  (nyan-mode 1))

(use-package which-key
  :ensure nil
  :hook (after-init . which-key-mode)
  :custom
  (which-key-idle-delay 0.4))

;;; Evil and leader keys

(use-package evil-numbers
  :after evil
  :demand t)

(use-package evil
  :demand t
  :config
  (evil-mode 1)
  (when (getenv "EMACS_SCRATCHPAD")
    (evil-insert-state))
  (define-key evil-insert-state-map (kbd "C-y") #'clipboard-yank)
  (define-key evil-normal-state-map (kbd "C-S-v") #'clipboard-yank)
  (define-key evil-emacs-state-map (kbd "C-y") #'clipboard-yank)
  (dolist (hook '(evil-normal-state-entry-hook
                  evil-insert-state-entry-hook
                  evil-visual-state-entry-hook
                  evil-replace-state-entry-hook
                  evil-operator-state-entry-hook
                  evil-motion-state-entry-hook
                  evil-emacs-state-entry-hook))
    (add-hook hook #'seli/apply-evil-cursor-shape))
  (seli/apply-evil-cursor-shape)
  (define-key evil-normal-state-map (kbd "U") #'evil-redo)
  (define-key evil-normal-state-map (kbd "C-b") nil)
  (define-key evil-normal-state-map (kbd "C-a") #'evil-numbers/inc-at-pt)
  (define-key evil-normal-state-map (kbd "C-x") #'evil-numbers/dec-at-pt))

(use-package evil-escape
  :after evil
  :custom
  (evil-escape-key-sequence "jj")
  (evil-escape-delay 0.25)
  (evil-escape-excluded-states '(normal visual replace operator motion emacs))
  :config
  (evil-escape-mode 1))

(use-package evil-collection
  :after evil
  :config
  (evil-collection-init))

(use-package eat
  :commands eat
  :hook (eat-mode . evil-insert-state))

(use-package general
  :demand t
  :after evil
  :config
  (general-create-definer seli/leader
    :states '(normal visual motion)
    :keymaps 'override
    :prefix "SPC"
    :non-normal-prefix "C-SPC")

  (defconst seli/toggle-term-buffer-name "*eat*")

  (defun seli/toggle-term--buffer ()
    "Return the reusable toggle terminal buffer, creating it if needed."
    (let ((buffer (get-buffer seli/toggle-term-buffer-name)))
      (when (and buffer
                 (not (process-live-p (get-buffer-process buffer))))
        (kill-buffer buffer)
        (setq buffer nil))
      (or buffer
          (progn
            ;; `eat' creates *eat* on first use and reuses it thereafter.
            ;; Preserve the current layout because the toggle function places
            ;; the buffer in its own bottom side window below.
            (save-window-excursion
              (eat))
            (get-buffer seli/toggle-term-buffer-name)))))

  (defun seli/toggle-term ()
    "Toggle a reusable terminal in a bottom side window."
    (interactive)
    (let* ((buffer (get-buffer seli/toggle-term-buffer-name))
           (window (and buffer
                        (get-buffer-window buffer (selected-frame)))))
      (if (window-live-p window)
          (delete-window window)
        (let ((window
               (display-buffer-in-side-window
                (seli/toggle-term--buffer)
                '((side . bottom)
                  (slot . -1)
                  (window-height . 0.33)
                  (window-parameters . ((no-delete-other-windows . t)))))))
          (set-window-dedicated-p window t)
          (select-window window)
          (when (fboundp 'evil-insert-state)
            (evil-insert-state))))))

  (global-set-key (kbd "C-\\") #'seli/toggle-term)

  (seli/leader
    "SPC" '(execute-extended-command :which-key "M-x")
    "d" '(dired-jump :which-key "filer")
    "n" '(consult-focus-lines :which-key "hide non-matches")
    "f" '(seli/consult-fd-buffer-tab :which-key "find files")
    "/" '(consult-ripgrep :which-key "grep")
    "m" '(consult-mark :which-key "marks")
    "u" '(undo-redo :which-key "undo redo")
    "s" '(consult-imenu :which-key "outline")
    "S" '(consult-org-heading :which-key "org headings")
    "t" '(:ignore t :which-key "toggle")
    "tb" '(seli/toggle-theme :which-key "toggle theme")
    "tt" '(seli/toggle-term :which-key "terminal")
    "o" '(:ignore t :which-key "org")
    "ot" '(org-todo :which-key "todo state")
    "oc" '(org-toggle-checkbox :which-key "toggle checkbox")
    "ol" '(org-insert-link :which-key "insert link")
    "oo" '(org-open-at-point :which-key "open link")
    "oi" '(org-toggle-inline-images :which-key "toggle images")))

(global-set-key (kbd "C-s") #'save-buffer)

;;; Completion, search, and navigation

(use-package vertico
  :hook (after-init . vertico-mode))

(defconst seli/vertico-posframe-mirror-buffer " *vertico-posframe-mirror*")

(defun seli/posframe-set-fixed-size-in-characters (set-size size-info)
  "Set fixed posframe SIZE-INFO in character units."
  (let ((posframe (plist-get size-info :posframe))
        (width (plist-get size-info :width))
        (height (plist-get size-info :height)))
    (if (and width height)
        (progn
          (set-frame-size posframe width height)
          (setq-local posframe--last-posframe-size size-info))
      (funcall set-size size-info))))

(defun seli/posframe-center-with-parent-metrics (info)
  "Center a fixed Vertico posframe using its parent frame metrics."
  (let* ((parent (plist-get info :parent-frame))
         (parent-width (plist-get info :parent-frame-width))
         (parent-height (plist-get info :parent-frame-height))
         (width (min vertico-posframe-width (frame-width parent)))
         (height (min vertico-posframe-height (frame-height parent)))
         (border-pixels (* 2 vertico-posframe-border-width))
         (pixel-width (+ border-pixels (* width (frame-char-width parent))))
         (pixel-height (+ border-pixels (* height (frame-char-height parent)))))
    (cons (max 0 (/ (- parent-width pixel-width) 2))
          (max 0 (/ (- parent-height pixel-height) 2)))))

(defun seli/posframe-mirror-live-minibuffer (show buffer-or-name &rest args)
  "Display a snapshot of a live minibuffer instead of the buffer itself."
  (if (not (and (buffer-live-p (get-buffer buffer-or-name))
                (minibufferp (get-buffer buffer-or-name))))
      (apply show buffer-or-name args)
    (let* ((parts
            (with-current-buffer buffer-or-name
              (let ((count (and (boundp 'vertico--count-ov)
                                (overlayp vertico--count-ov)
                                (overlay-get vertico--count-ov 'before-string)))
                    (candidates (and (boundp 'vertico--candidates-ov)
                                     (overlayp vertico--candidates-ov)
                                     (overlay-get vertico--candidates-ov 'before-string))))
                (list (or count "")
                      (buffer-substring (point-min) (point-max))
                      (or candidates "")))))
           (count-width (length (car parts)))
           (string (apply #'concat parts))
           (window-point (plist-get args :window-point)))
      (with-current-buffer (get-buffer-create seli/vertico-posframe-mirror-buffer)
        (setq-local face-remapping-alist nil
                    text-scale-mode nil
                    text-scale-mode-amount 0))
      (setq args (plist-put args :string string))
      (when window-point
        (setq args (plist-put args :window-point (+ count-width window-point))))
      ;; The standard handler tests whether the displayed buffer itself is a
      ;; minibuffer.  The mirror is intentionally not one, so Vertico's exit
      ;; hook below is responsible for hiding it.
      (setq args (plist-put args :hidehandler nil))
      (prog1 (apply show seli/vertico-posframe-mirror-buffer args)
        ;; `posframe--create-posframe' calls `text-scale-set'.  On a daemon
        ;; child frame its bogus initial line height can leave a 1/21 face
        ;; remap behind, so reset the display-only mirror after creation too.
        (with-current-buffer seli/vertico-posframe-mirror-buffer
          (setq-local face-remapping-alist nil
                      text-scale-mode nil
                      text-scale-mode-amount 0))
        (force-window-update seli/vertico-posframe-mirror-buffer)))))

(defun seli/posframe-hide-minibuffer-mirror (hide buffer-or-name)
  "Hide BUFFER-OR-NAME and its Vertico mirror, when applicable."
  (prog1 (funcall hide buffer-or-name)
    (when (and (buffer-live-p (get-buffer buffer-or-name))
               (minibufferp (get-buffer buffer-or-name)))
      (funcall hide seli/vertico-posframe-mirror-buffer))))

;; Show minibuffer completion UIs such as M-x in a centered floating frame.
(use-package vertico-posframe
  :after vertico
  :demand t
  :custom
  (vertico-posframe-poshandler #'seli/posframe-center-with-parent-metrics)
  (vertico-posframe-width 100)
  (vertico-posframe-height 20)
  :config
  (advice-add 'posframe-show :around #'seli/posframe-mirror-live-minibuffer)
  (advice-add 'posframe-hide :around #'seli/posframe-hide-minibuffer-mirror)
  (advice-add 'posframe--set-frame-size
              :around #'seli/posframe-set-fixed-size-in-characters)
  (vertico-posframe-mode 1))

(use-package hotfuzz
  :demand t)

(use-package orderless
  :custom
  (completion-styles '(orderless basic))
  (completion-category-defaults nil)
  (completion-category-overrides '((file (styles hotfuzz partial-completion basic)))))

(use-package marginalia
  :hook (after-init . marginalia-mode))

(use-package consult
  :bind (("C-x b" . consult-buffer)
         ("M-y" . consult-yank-pop))
  :custom
  (consult-fd-args "fd --color=never --hidden --exclude .git")
  (consult-ripgrep-args "rg --null --line-buffered --color=never --max-columns=1000 --path-separator / --smart-case --hidden --glob !.git"))

(defun seli/consult-fd-buffer-tab ()
  "Find files with `consult-fd', showing opened buffers in `tab-line-mode'."
  (interactive)
  (call-interactively #'consult-fd))

(defun seli/ghq-open-repository ()
  "Select a ghq repository with completion and open its root directory."
  (interactive)
  (unless (executable-find "ghq")
    (user-error "ghq is not available"))
  (let* ((root (car (process-lines "ghq" "root")))
         (repositories (process-lines "ghq" "list"))
         (repository
          (if repositories
              (completing-read "Repository: " repositories nil t)
            (user-error "No ghq repositories found"))))
    (find-file (expand-file-name repository root))))

(global-set-key (kbd "C-c g") #'seli/ghq-open-repository)

(with-eval-after-load 'general
  (seli/leader
    "p" '(:ignore t :which-key "project")
    "pg" '(seli/ghq-open-repository :which-key "open ghq repository")))

(use-package corfu
  :hook (after-init . global-corfu-mode)
  :custom
  (corfu-auto t)
  (corfu-auto-delay 0.15)
  (corfu-auto-prefix 2)
  (corfu-cycle t)
  (corfu-quit-no-match 'separator)
  :bind (:map corfu-map
              ("RET" . corfu-insert)
              ("<return>" . corfu-insert)))

(use-package cape
  :after corfu
  :demand t
  :init
  (add-to-list 'completion-at-point-functions #'cape-dabbrev)
  (setq completion-at-point-functions
        (cons #'cape-file
              (delq #'cape-file completion-at-point-functions)))
  :config
  (defun seli/enable-path-completion ()
    "Prefer file-path completion in the current buffer.

`cape-file' completes relative paths after `./' and absolute paths after `/'.
It is installed buffer-locally so LSP completion remains available for normal
identifiers."
    (setq-local completion-at-point-functions
                (cons #'cape-file
                      (delq #'cape-file completion-at-point-functions))))
  (add-hook 'prog-mode-hook #'seli/enable-path-completion)
  (add-hook 'eglot-managed-mode-hook #'seli/enable-path-completion))

;;; Programming

;; Import direnv environments buffer-locally.  In projects whose .envrc uses
;; `use flake`, formatters and language servers from `nix develop` become
;; available to Apheleia and Eglot without changing the daemon-wide PATH.
(use-package envrc
  :demand t
  :config
  (envrc-global-mode 1))

;; These packages provide major modes and font-lock for languages also used in
;; the Neovim configuration.  Built-in modes cover C/C++, Python, shell,
;; JavaScript, CSS, and JSON; the packages below cover the remaining formats.
(use-package nix-mode :mode "\\.nix\\'")
(use-package rust-mode :mode "\\.rs\\'")
(use-package go-mode :mode "\\.go\\'")
(use-package lua-mode :mode "\\.lua\\'")
(use-package zig-mode :mode "\\.zig\\'")
(use-package typst-ts-mode :mode "\\.typ\\'")
(use-package kdl-mode :mode "\\.kdl\\'")
(use-package json-mode :mode "\\.jsonc?\\'")
(use-package web-mode
  :mode ("\\.astro\\'" "\\.tsx?\\'" "\\.jsx\\'"))

(defun seli/scratchpad-frame-p ()
  "Return non-nil when the selected frame is the Scratchpad Emacs frame."
  (equal (frame-parameter nil 'title) "Scratchpad Emacs"))

;; Format supported buffers asynchronously on save, preserving point and
;; scroll position.  Apheleia already maps shfmt, nixfmt, rustfmt, gofmt,
;; stylua, clang-format, taplo, and Prettier-backed web modes.
(use-package apheleia
  :demand t
  :config
  ;; Match the Neovim setup by using the installed Biome binary for web data
  ;; formats instead of requiring a project-local Prettier installation.
  (setf (alist-get 'biome apheleia-formatters)
        '("biome" "format" "--stdin-file-path" filepath))
  (dolist (mode '(js-mode js-ts-mode json-mode json-ts-mode css-mode css-ts-mode
                          typescript-ts-mode tsx-ts-mode))
    (setf (alist-get mode apheleia-mode-alist) 'biome))
  ;; The scratchpad is a titled frame in the regular daemon, not a separate
  ;; process, so inhibit each operation according to the selected frame.
  (add-to-list 'apheleia-skip-functions #'seli/scratchpad-frame-p)
  (apheleia-global-mode 1))

;; Eglot is built into Emacs.  It starts the same language servers used by the
;; rest of this dotfiles setup and publishes diagnostics through Flymake.
(use-package eglot
  :ensure nil
  :demand t
  :hook ((nix-mode . eglot-ensure)
         (rust-mode . eglot-ensure)
         (go-mode . eglot-ensure)
         (zig-mode . eglot-ensure)
         (typst-ts-mode . eglot-ensure)
         (c-mode . eglot-ensure)
         (c++-mode . eglot-ensure)
         (js-mode . eglot-ensure)
         (json-mode . eglot-ensure)
         (css-mode . eglot-ensure))
  :config
  (dolist (entry
           '(((nix-mode nix-ts-mode) . ("nil"))
             ((rust-mode rust-ts-mode) . ("rust-analyzer"))
             ((go-mode go-ts-mode) . ("gopls"))
             ((zig-mode zig-ts-mode) . ("zls"))
             ((typst-ts-mode) . ("tinymist"))
             ((c-mode c++-mode c-ts-mode c++-ts-mode) . ("clangd"))
             ((js-mode js-ts-mode json-mode json-ts-mode css-mode css-ts-mode
                       typescript-ts-mode tsx-ts-mode) . ("biome" "lsp-proxy"))))
    (add-to-list 'eglot-server-programs entry)))

(with-eval-after-load 'general
  (seli/leader
    "l" '(:ignore t :which-key "language")
    "la" '(eglot-code-actions :which-key "code action")
    "ld" '(xref-find-definitions :which-key "definition")
    "lr" '(eglot-rename :which-key "rename")
    "lf" '(apheleia-format-buffer :which-key "format")))

;; The systemd daemon explicitly loads this file with --load, which happens
;; after Emacs's normal init phase.  Run deferred startup hooks once here so
;; Corfu and other `after-init-hook' packages are enabled in that case too.
(defvar seli/after-init-hooks-ran nil)
(add-hook 'after-init-hook (lambda () (setq seli/after-init-hooks-ran t)))
(when (and after-init-time (not seli/after-init-hooks-ran))
  (run-hooks 'after-init-hook))

;;; Org mode

(defun seli/org-mode-defaults ()
  "Prose-friendly defaults for `org-mode' buffers."
  ;; Org syntax defines a TAB as eight columns.  A different value can corrupt
  ;; org-element's position cache even when indentation itself uses spaces.
  (setq-local tab-width 8
              truncate-lines nil))

(defun seli/org-insert-current-timestamp ()
  "Insert the current date and time as an active Org timestamp at point."
  (interactive)
  (org-insert-time-stamp (current-time) t))

(defun seli/org-meta-return-and-insert (&optional arg)
  "Create an Org heading with `org-meta-return', then enter Insert state."
  (interactive "P")
  (org-meta-return arg)
  (evil-insert-state))

(defun seli/org-open-link-in-new-tab ()
  "Open the Org link at point in a new Emacs tab, if there is one."
  (interactive)
  (when (eq (org-element-type (org-element-context)) 'link)
    (tab-new)
    (org-open-at-point)))

(use-package org
  :ensure nil
  :mode ("\\.org\\'" . org-mode)
  :hook ((org-mode . visual-line-mode)
         (org-mode . seli/org-mode-defaults))
  :custom
  (org-directory "~/org")
  (org-startup-indented t)
  (org-startup-folded 'content)
  (org-startup-with-inline-images t)
  (org-image-actual-width '(600))
  (org-pretty-entities t)
  (org-use-sub-superscripts nil)
  (org-hide-emphasis-markers t)
  (org-ellipsis " ▾")
  (org-fontify-quote-and-verse-blocks t)
  (org-return-follows-link t)
  (org-insert-heading-respect-content t)
  (org-catch-invisible-edits 'show-and-error)
  (org-auto-align-tags nil)
  (org-tags-column 0))

;; `<q' TAB などのブロックテンプレート。
(use-package org-tempo
  :ensure nil
  :after org
  :demand t)

(use-package evil-org
  :after (evil org)
  :hook (org-mode . evil-org-mode)
  :config
  (evil-org-set-key-theme '(navigation insert textobjects additional calendar))
  (evil-define-key 'normal evil-org-mode-map
    (kbd "M-<return>") #'seli/org-meta-return-and-insert)
  (evil-define-key '(normal insert) evil-org-mode-map
    (kbd "C-c .") #'seli/org-insert-current-timestamp
    (kbd "S-<return>") #'seli/org-open-link-in-new-tab))

(with-eval-after-load 'org
  (define-key org-mode-map (kbd "S-<return>") #'seli/org-open-link-in-new-tab))

(use-package org-modern
  :hook (org-mode . org-modern-mode)
  :custom
  (org-modern-star 'replace)
  (org-modern-hide-stars nil)
  (org-modern-table t)
  ;; Keep TODO keywords and tags in Org's standard text style.
  (org-modern-todo nil)
  (org-modern-tag nil)
  (org-modern-list '((?+ . "◦") (?- . "–") (?* . "•"))))

;; Keep Org markup visually quiet, but reveal the source of the element at
;; point so links such as [[URL][label]] remain straightforward to edit.
(use-package org-appear
  :after org
  :hook (org-mode . org-appear-mode)
  :custom
  (org-appear-autolinks t)
  (org-appear-autoemphasis t)
  (org-appear-autoentities t)
  (org-appear-autosubmarkers t))

;;; Git

(use-package magit
  :bind ("C-x g" . magit-status))

(defun seli/diff-hl-enable-gui-margin (&optional frame)
  "Show Git change markers beside line numbers in graphical FRAMEs."
  (when (display-graphic-p frame)
    (diff-hl-margin-mode 1)))

(use-package diff-hl
  :demand t
  :config
  ;; Update markers while editing as well as after saving.  `diff-hl-margin-mode'
  ;; puts them in the left margin, next to the line-number column.
  (global-diff-hl-mode 1)
  (diff-hl-flydiff-mode 1)
  (seli/diff-hl-enable-gui-margin)
  (add-hook 'after-make-frame-functions #'seli/diff-hl-enable-gui-margin)
  (with-eval-after-load 'magit
    (add-hook 'magit-post-refresh-hook #'diff-hl-magit-post-refresh)))

;;; Git status in the mode line

(defconst seli/git-status-categories
  '((conflict . "!")
    (staged . "+")
    (modified . "~")
    (deleted . "-")
    (renamed . "\u00bb")
    (untracked . "?"))
  "Ordered Git file states and the symbols shown in the mode line.")

(defconst seli/git-status-faces
  '((conflict . doom-modeline-urgent)
    (staged . doom-modeline-info)
    (modified . doom-modeline-warning)
    (deleted . doom-modeline-urgent)
    (renamed . doom-modeline-info)
    (untracked . doom-modeline-info))
  "Faces used for each Git file state in the mode line.")

(defvar-local seli/git-status-counts nil
  "Per-category count of changed files in the current buffer's repository.")

(defvar-local seli/git-status--process nil
  "The Git process currently computing `seli/git-status-counts'.")

(defun seli/git-status--inc (counts category)
  "Increment the file count for CATEGORY in COUNTS."
  (let ((cell (assq category counts)))
    (setcdr cell (1+ (cdr cell)))))

(defun seli/git-status--counts (output)
  "Count changed files by state from `git status --porcelain' OUTPUT."
  (let ((counts (mapcar (lambda (cell) (cons (car cell) 0))
                        seli/git-status-categories)))
    (dolist (line (split-string output "\n" t))
      (when (>= (length line) 2)
        (let ((x (aref line 0))
              (y (aref line 1)))
          (cond
           ((and (eq x ??) (eq y ??))
            (seli/git-status--inc counts 'untracked))
           ((or (eq x ?U) (eq y ?U)
                (and (eq x ?A) (eq y ?A))
                (and (eq x ?D) (eq y ?D)))
            (seli/git-status--inc counts 'conflict))
           (t
            (pcase x
              ((or ?A ?M ?C ?D) (seli/git-status--inc counts 'staged))
              (?R (seli/git-status--inc counts 'renamed)))
            (pcase y
              (?M (seli/git-status--inc counts 'modified))
              (?D (seli/git-status--inc counts 'deleted))))))))
    counts))

(defun seli/git-status-refresh ()
  "Recompute the cached Git file counts for the current buffer."
  (when (process-live-p seli/git-status--process)
    (delete-process seli/git-status--process))
  (setq seli/git-status--process nil
        seli/git-status-counts nil)
  (when-let* ((file buffer-file-name)
              ((not (file-remote-p file)))
              ((locate-dominating-file file ".git")))
    (let ((buffer (current-buffer))
          (output ""))
      (setq seli/git-status--process
            (make-process
             :name "seli-git-status"
             :noquery t
             :command '("git" "--no-optional-locks" "status" "--porcelain")
             :filter (lambda (_process chunk)
                       (setq output (concat output chunk)))
             :sentinel (lambda (process _event)
                         (when (and (eq (process-status process) 'exit)
                                    (zerop (process-exit-status process))
                                    (buffer-live-p buffer))
                           (with-current-buffer buffer
                             (setq seli/git-status-counts
                                   (seli/git-status--counts output))
                             (force-mode-line-update)))))))))

(defun seli/git-status--kill ()
  "Stop a running Git status process when its buffer is killed."
  (when (process-live-p seli/git-status--process)
    (delete-process seli/git-status--process)))

(add-hook 'find-file-hook #'seli/git-status-refresh)
(add-hook 'after-save-hook #'seli/git-status-refresh)
(add-hook 'kill-buffer-hook #'seli/git-status--kill)
(advice-add #'vc-refresh-state :after #'seli/git-status-refresh)

(defconst seli/evil-state-faces
  '((normal . doom-modeline-evil-normal-state)
    (emacs . doom-modeline-evil-emacs-state)
    (insert . doom-modeline-evil-insert-state)
    (motion . doom-modeline-evil-motion-state)
    (visual . doom-modeline-evil-visual-state)
    (operator . doom-modeline-evil-operator-state)
    (replace . doom-modeline-evil-replace-state))
  "Faces used for each Evil state in the mode line.")

(defconst seli/evil-state-names
  '((normal . "NORMAL")
    (emacs . "EMACS")
    (insert . "INSERT")
    (motion . "MOTION")
    (visual . "VISUAL")
    (operator . "OPERATOR")
    (replace . "REPLACE"))
  "Readable names for each Evil state, shown as text in the mode line.")

(with-eval-after-load 'doom-modeline
  (doom-modeline-def-segment git-status
    "Displays Git file-change counts, e.g. `~8 -70'."
    (when seli/git-status-counts
      (let ((parts
             (delq nil
                   (mapcar
                    (lambda (cell)
                      (let* ((category (car cell))
                             (count (cdr (assq category seli/git-status-counts))))
                        (when (and count (> count 0))
                          (propertize (format "%s%d" (cdr cell) count)
                                      'face (cdr (assq category seli/git-status-faces))))))
                    seli/git-status-categories))))
        (when parts
          (concat (doom-modeline-spc) (mapconcat #'identity parts " "))))))

  (doom-modeline-def-segment evil-state
    "Displays the current Evil state as text, e.g. NORMAL."
    (when (bound-and-true-p evil-local-mode)
      (let ((name (or (cdr (assq evil-state seli/evil-state-names))
                      (upcase (symbol-name evil-state))))
            (face (or (cdr (assq evil-state seli/evil-state-faces))
                      'doom-modeline-evil-user-state)))
        (concat (doom-modeline-spc)
                (propertize name 'face face)
                (doom-modeline-spc)))))

  (doom-modeline-def-segment nyan
    "Displays the Nyan cat progress indicator on its own."
    (when (bound-and-true-p nyan-mode)
      (concat (doom-modeline-spc) (nyan-create) (doom-modeline-spc))))

  (doom-modeline-def-segment position
    "Displays line/column and percentage without the Nyan cat."
    (let ((nyan-mode nil))
      (doom-modeline-segment--buffer-position)))

  ;; Mode-line layout:
  ;; left  : evil state, Git branch, changed-file counts, path
  ;; right : lang, file size, Nyan cat, buffer position
  (doom-modeline-def-modeline 'main
    '(evil-state
      vcs
      git-status
      buffer-info)
    '(major-mode
      buffer-size
      nyan
      position)))

;;; Files

(defun seli/dired-find-file-in-new-tab ()
  "Visit a file at point in a new tab, or a directory in the current tab."
  (interactive)
  (let ((file (dired-get-file-for-visit)))
    (if (file-directory-p file)
        (dired-find-file)
      (tab-new)
      (find-file file))))

(use-package dired
  :ensure nil
  :hook (dired-mode . dired-hide-details-mode)
  :custom
  (dired-listing-switches "-alh --group-directories-first")
  :config
  (with-eval-after-load 'evil
    (evil-define-key 'normal dired-mode-map
      (kbd "RET") #'seli/dired-find-file-in-new-tab
      (kbd "<return>") #'seli/dired-find-file-in-new-tab
      (kbd "l") #'seli/dired-find-file-in-new-tab
      (kbd "h") #'dired-up-directory
      (kbd "^") #'dired-up-directory
      (kbd "q") #'quit-window)))

;;; Final local customizations

(when (file-exists-p custom-file)
  (load custom-file nil t))

;;; capture

(require 'org)
(require 'org-id)
(require 'vc-git)

(setq org-default-notes-file "~/org/inbox.org")
(setq org-agenda-files
      (when (file-directory-p org-directory)
        (directory-files-recursively org-directory "\\.org$")))
(setq org-todo-keywords
      '((sequence "TODO(t)" "WAIT(w)" "|" "NOTING(n)" "DONE(d)" "CANCELLED(c)")))

(defvar seli/org-inbox-file (expand-file-name "inbox.org" org-directory)
  "The temporary Org inbox file.")

(defvar seli/org-notes-file (expand-file-name "notes.org" org-directory)
  "The permanent Org notes file.")

(defun seli/org-inbox-subtree-to-notes ()
  "Move the Inbox subtree at point into notes.org as a level-one entry.

The source subtree is replaced with an ID link.  The destination root heading
is always level one; its former TODO state, priority, and tags are omitted.
Child headings keep their relative depth."
  (interactive)
  (unless (derived-mode-p 'org-mode)
    (user-error "This command is only available in Org buffers"))
  (unless (and buffer-file-name
               (file-equal-p buffer-file-name seli/org-inbox-file))
    (user-error "This command only moves headings from %s" seli/org-inbox-file))
  (org-back-to-heading t)
  (let* ((source-buffer (current-buffer))
         (title (org-get-heading t t t t))
         (id (org-id-get-create))
         (level (org-outline-level))
         (begin (point))
         (end (save-excursion (org-end-of-subtree t t)))
         (subtree (buffer-substring-no-properties begin end))
         (first-newline (or (string-match "\n" subtree) (length subtree)))
         (body (substring subtree first-newline))
         (notes-subtree
          (concat
           "* " title
           (replace-regexp-in-string
            "^\\(\\*+\\) "
            (lambda (heading)
              (let ((stars (car (split-string heading " "))))
                (concat (make-string (max 1 (1+ (- (length stars) level))) ?*) " ")))
            body)))
         (link (format "[[id:%s][%s]]" id title)))
    (with-current-buffer (find-file-noselect seli/org-notes-file)
      (goto-char (point-max))
      (unless (bolp) (insert "\n"))
      (unless (bobp) (insert "\n"))
      (insert notes-subtree)
      (unless (bolp) (insert "\n"))
      (save-buffer))
    (org-id-add-location id seli/org-notes-file)
    (with-current-buffer source-buffer
      (save-excursion
        (goto-char begin)
        (delete-region begin end)
        (insert (make-string level ?*) " " link "\n"))
      (save-buffer))
    (message "Moved \"%s\" to notes.org" title)))

(define-key org-mode-map (kbd "C-c C-x n") #'seli/org-inbox-subtree-to-notes)

(defvar seli/org-capture-git-queue nil
  "Capture files waiting to be committed as (REPOSITORY . FILE) pairs.")

(defvar seli/org-capture-git-process nil
  "The Git process currently handling an Org capture commit.")

(defun seli/org-capture-git-start (repository file step command)
  "Run Git COMMAND asynchronously for FILE in REPOSITORY at STEP."
  (let ((default-directory repository)
        (process-environment (cons "GIT_TERMINAL_PROMPT=0" process-environment)))
    (setq seli/org-capture-git-process
          (make-process
           :name "org-capture-git"
           :buffer (get-buffer-create " *org-capture-git*")
           :command command
           :noquery t
           :sentinel #'seli/org-capture-git-sentinel))
    (process-put seli/org-capture-git-process 'repository repository)
    (process-put seli/org-capture-git-process 'file file)
    (process-put seli/org-capture-git-process 'step step)))

(defun seli/org-capture-git-run-next ()
  "Start the next queued capture commit, if any."
  (unless (process-live-p seli/org-capture-git-process)
    (when-let* ((entry (pop seli/org-capture-git-queue))
                (repository (car entry))
                (file (cdr entry)))
      (seli/org-capture-git-start
       repository file 'add (list "git" "add" "--" file)))))

(defun seli/org-capture-git-sentinel (process _event)
  "Continue PROCESS's asynchronous add, check, and commit sequence."
  (when (memq (process-status process) '(exit signal))
    (let ((repository (process-get process 'repository))
          (file (process-get process 'file))
          (step (process-get process 'step))
          (status (process-exit-status process)))
      (setq seli/org-capture-git-process nil)
      (cond
       ((not (zerop status))
        ;; `git diff --quiet' uses status 1 to report staged changes.
        (if (and (eq step 'diff) (= status 1))
            (seli/org-capture-git-start
             repository file 'commit
             (list "git" "commit" "-m"
                   (format "org capture: %s" (format-time-string "%F %R"))
                   "--" file))
          (message "Org capture Git %s failed for %s (exit %d)"
                   step file status)
          (seli/org-capture-git-run-next)))
       ((eq step 'add)
        (seli/org-capture-git-start
         repository file 'diff (list "git" "diff" "--cached" "--quiet" "--" file)))
       ((eq step 'diff)
        (message "Org capture: no Git changes to commit for %s" file)
        (seli/org-capture-git-run-next))
       ((eq step 'commit)
        (message "Org capture committed %s" file)
        (seli/org-capture-git-run-next))))))

(defun seli/org-capture-queue-git-commit ()
  "Asynchronously commit the file written by a finalized Org capture."
  (unless org-note-abort
    (when-let* ((file (buffer-file-name (org-capture-get :buffer)))
                (repository (vc-git-root file)))
      (let ((entry (cons repository (file-relative-name file repository))))
        (unless (member entry seli/org-capture-git-queue)
          (push entry seli/org-capture-git-queue))
        (seli/org-capture-git-run-next)))))

(add-hook 'org-capture-after-finalize-hook #'seli/org-capture-queue-git-commit)

(setq org-capture-templates
      '(        ("t" "Todo" entry
                 (file "~/org/inbox.org")
                 "* TODO %?\n:PROPERTIES:\n:CREATED: %U\n:END:\n")

                ("n" "Note" entry
                 (file "~/org/notes.org")
                 "* %?\n%U\n")

                ("j" "Journal" plain
                 (file+datetree "~/org/journal.org")
                 "%?\n")))

(global-set-key (kbd "C-c c") #'org-capture)
(global-set-key (kbd "C-c a") #'org-agenda)
