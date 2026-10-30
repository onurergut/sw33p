# Known limitations

- APFS clones are not detected, so reported savings can exceed the space the
  volume actually frees.
- Moving items to the Trash does not free disk space until the Trash is emptied.
- Hard links are counted once inside each candidate subtree. Two separate
  candidates that share a hard-linked file can still both count it, so a
  combined total can double-count that file.
- Homebrew cleanup runs `brew cleanup`; sw33p does not reimplement Homebrew's
  policy and cannot preview exactly which files it will remove.
- A managed command cannot be paused once it starts. Cancellation or timeout
  sends `SIGTERM`, then `SIGKILL` after a 2-second grace period, and the runner
  waits for termination, bounded by the command timeout plus the grace period.
- Xcode DeviceSupport folders are safe to remove, but debugging on that OS
  version downloads the symbols again.
- Xcode Archives are not reproducible. Removing them can make older crash
  reports unsymbolicated. They are listed with a warning and are not
  preselected; nothing is selected by default.
- Protected folders (Desktop, Documents, Downloads, external volumes) may
  require Full Disk Access. Unreadable folders are reported, never guessed at.
- Scanning a home folder with millions of files takes time; progress is shown
  and the scan is cancellable.
- No scheduled cleaning, menu bar mode, Windows, or Linux.
