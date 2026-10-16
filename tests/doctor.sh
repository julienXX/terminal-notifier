#!/bin/bash
# terminal-notifier doctor
#
# Checks that every option the help banner advertises actually works, and
# reports what is wrong when it does not.
#
#   tests/doctor.sh              full run, prompts you for the interactive parts
#   tests/doctor.sh --unattended skips anything needing a person (for CI)
#
# Delivering a notification needs a granted permission and a logged-in GUI
# session. Neither can be arranged non-interactively, so when they are missing
# those checks are reported as skipped rather than failed, and the exit status
# stays 0.

set -u

UNATTENDED=0
[ "${1:-}" = "--unattended" ] && UNATTENDED=1

cd "$(dirname "$0")/.."

APP="build/terminal-notifier.app"
BIN="$APP/Contents/MacOS/terminal-notifier"
PLIST="Terminal Notifier/Terminal Notifier-Info.plist"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST" 2>/dev/null)"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST" 2>/dev/null)"

PASS=0; FAIL=0; SKIP=0
TNExitBadArgument=2
PROBLEMS=()

if [ -t 1 ]; then
  G=$'\033[32m'; R=$'\033[31m'; Y=$'\033[33m'; C=$'\033[36m'; B=$'\033[1m'; Z=$'\033[0m'
else
  G=; R=; Y=; C=; B=; Z=
fi

ok()   { printf "  ${G}ok${Z}    %s\n" "$1"; PASS=$((PASS + 1)); }
bad()  { printf "  ${R}FAIL${Z}  %s\n" "$1"; [ $# -gt 1 ] && printf "        %s\n" "$2"
         FAIL=$((FAIL + 1)); PROBLEMS+=("$1"); }
skip() { printf "  ${Y}skip${Z}  %s\n" "$1"; [ $# -gt 1 ] && printf "        %s\n" "$2"
         SKIP=$((SKIP + 1)); }
section() { printf "\n${B}%s${Z}\n" "$1"; }

# Compare an actual value with an expected one.
is() { # is <label> <actual> <expected>
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "got '$2', expected '$3'"; fi
}

# Run the binary and check its exit status.
exits() { # exits <label> <expected status> <args...>
  local label="$1" want="$2"; shift 2
  "$BIN" "$@" >/dev/null 2>&1 </dev/null
  is "$label" "$?" "$want"
}

notifications() { "$BIN" -list ALL 2>/dev/null | tail -n +2 | grep -c . | tr -d ' '; }
pending()       { "$BIN" -list PENDING 2>/dev/null | tail -n +2 | grep -c . | tr -d ' '; }
clear_all()     { "$BIN" -remove ALL >/dev/null 2>&1; sleep 1; }
# field <n> — nth tab separated column of the first listed notification
field()         { "$BIN" -list ALL 2>/dev/null | tail -n +2 | head -1 | cut -f"$1"; }

# --- interactive helpers -----------------------------------------------------
# /dev/tty can exist yet not be readable, so try opening it rather than
# testing for it. Otherwise the prompts below get recorded as broken features.
TTY_OK=0
if [ -e /dev/tty ] && (exec </dev/tty) 2>/dev/null; then TTY_OK=1; fi

tell() { printf "  ${C}-->${Z}   %s\n" "$1"; }
confirm() { # confirm <question>  -> 0 for yes
  local answer
  printf "        %s [y/n] " "$1"
  read -r answer </dev/tty || return 1
  case "$answer" in [yY]*) return 0 ;; *) return 1 ;; esac
}

printf "${B}terminal-notifier doctor${Z}  (%s)\n" "${VERSION:-unknown}"

# =============================================================================
section "Build"

if [ ! -x "$BIN" ]; then
  bad "the app is built" "no $BIN — run: make app"
  printf "\nCannot continue without a build.\n"
  exit 1
fi
ok "the app is built"

archs="$(lipo -info "$BIN" 2>/dev/null)"
case "$archs" in
  *arm64*x86_64*|*x86_64*arm64*) ok "universal binary (x86_64 + arm64)" ;;
  *) bad "universal binary" "only: $archs" ;;
esac

if codesign --verify --strict "$APP" >/dev/null 2>&1; then
  ok "code signature verifies"
else
  bad "code signature verifies" "notifications need a stable signed identity"
fi

id_in_bundle="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist" 2>/dev/null)"
is "bundle identifier is $BUNDLE_ID" "$id_in_bundle" "$BUNDLE_ID"

if otool -l "$BIN" 2>/dev/null | grep -q "minos 10.14"; then
  ok "deployment target is 10.14"
else
  bad "deployment target is 10.14" "$(otool -l "$BIN" | grep -m1 minos)"
fi

# =============================================================================
section "Options that need no notification"

exits "-version exits 0"                       0 -version
exits "-help exits 0"                          0 -help
exits "no arguments is a usage error"          1
exits "a malformed -open is rejected"          2 -message x -open 'not a uri'
exits "a non-positive -timeout is rejected"    2 -message x -action Yes -timeout 0
exits "an unreadable -message is rejected"     2 -message '[unescaped'
exits "-in and -at cannot be combined"         2 -message x -in 5m -at 09:15
exits "a scheduled -action is rejected"        2 -message x -in 5m -action Yes
exits "a scheduled -reply is rejected"         2 -message x -in 5m -reply
exits "a malformed -in is rejected"            2 -message x -in 5min
exits "a zero -in is rejected"                 2 -message x -in 0
exits "an unreadable -in is rejected"          2 -message x -in -5
exits "a malformed -at is rejected"            2 -message x -at 25:00
exits "an impossible date is rejected"         2 -message x -at '2026-02-30 02:00'
exits "a past -at is rejected"                 2 -message x -at '2020-01-01 00:00'

is "-version reports $VERSION" "$("$BIN" -version 2>/dev/null | awk '{print $2}' | tr -d '.')" "$(echo "$VERSION" | tr -d '.')"

banner="$("$BIN" -help 2>/dev/null)"
missing=""
for opt in -help -version -diagnose -message -remove -list -title -subtitle \
           -sound -group -activate -contentImage -open -execute -action \
           -reply -timeout -timeSensitive -ignoreDnD "-in DURATION" "-at TIME" -sender -appIcon; do
  case "$banner" in *"$opt"*) ;; *) missing="$missing $opt" ;; esac
done
if [ -z "$missing" ]; then
  ok "the banner documents all 23 options"
else
  bad "the banner documents all 23 options" "missing:$missing"
fi

# =============================================================================
section "Environment"

diag="$("$BIN" -diagnose 2>/dev/null)"
diag_status=$?

show() { # show <label> <row prefix>
  local value
  value="$(printf '%s\n' "$diag" | grep -m1 "  $2" | sed "s/.*$2 *//")"
  printf "  ${C}info${Z}  %-22s %s\n" "$1" "${value:-unknown}"
}
show "authorization"      "authorization"
show "alerts"             "alerts"
show "alert style"        "alert style"
show "sounds"             "sounds"
show "NotificationCenter" "NotificationCenter"

CAN_DELIVER=0
case "$diag" in
  *"authorization       authorized"*|*"authorization       provisional"*) CAN_DELIVER=1 ;;
esac
case "$diag" in *"NOT RUNNING"*) CAN_DELIVER=0 ;; esac

if [ "$CAN_DELIVER" = 1 ]; then
  ok "notifications can be delivered"
else
  skip "notifications can be delivered" \
       "see the rows above; run '$BIN -diagnose' for the full report"
fi

# =============================================================================
section "Delivery"

if [ "$CAN_DELIVER" = 0 ]; then
  skip "every delivery check" "notifications are not available in this session"
else
  clear_all

  "$BIN" -message 'doctor: plain' >/dev/null 2>&1
  sleep 1
  is "-message delivers" "$(notifications)" "1"

  clear_all
  "$BIN" -title 'DocTitle' -subtitle 'DocSubtitle' -message 'DocBody' >/dev/null 2>&1
  sleep 1
  is "-title is recorded"    "$(field 2)" "DocTitle"
  is "-subtitle is recorded" "$(field 3)" "DocSubtitle"
  is "-message is recorded"  "$(field 4)" "DocBody"

  # -list shape
  header="$("$BIN" -list ALL 2>/dev/null | head -1)"
  is "-list prints a header row" "$header" "$(printf 'GroupID\tTitle\tSubtitle\tMessage\tDelivered At')"
  is "-list rows have 5 columns" "$("$BIN" -list ALL 2>/dev/null | tail -n +2 | head -1 | awk -F'\t' '{print NF}')" "5"

  # Ungrouped notifications must not replace each other.
  clear_all
  for n in one two three; do "$BIN" -message "doctor: $n" >/dev/null 2>&1; done
  sleep 1
  is "three ungrouped sends give three notifications" "$(notifications)" "3"

  # -group replaces in place.
  clear_all
  "$BIN" -message 'doctor: first' -group doctor >/dev/null 2>&1; sleep 1
  "$BIN" -message 'doctor: second' -group doctor >/dev/null 2>&1; sleep 1
  is "-group replaces the previous notification" "$(notifications)" "1"
  is "-group keeps the newest message" "$(field 4)" "doctor: second"
  is "-group is recorded" "$(field 1)" "doctor"

  # -remove
  "$BIN" -remove doctor >/dev/null 2>&1; sleep 1
  is "-remove removes the group" "$(notifications)" "0"

  clear_all
  "$BIN" -message 'doctor: a' >/dev/null 2>&1
  "$BIN" -message 'doctor: b' >/dev/null 2>&1; sleep 1
  "$BIN" -remove ALL >/dev/null 2>&1; sleep 1
  is "-remove ALL removes everything" "$(notifications)" "0"

  # Scheduling. Far enough out that it never fires during the run.
  clear_all
  "$BIN" -message 'doctor: later' -group sched -in 1h >/dev/null 2>&1; sleep 1
  is "-in does not deliver immediately"  "$(notifications)" "0"
  is "-in shows up in -list PENDING"     "$(pending)" "1"
  is "-list PENDING has a Scheduled For header" \
     "$("$BIN" -list PENDING 2>/dev/null | head -1 | cut -f5)" "Scheduled For"
  is "-list PENDING rows have 5 columns" \
     "$("$BIN" -list PENDING 2>/dev/null | tail -n +2 | head -1 | awk -F'\t' '{print NF}')" "5"

  "$BIN" -message 'doctor: at' -group sched2 -at '2027-03-04 05:06' >/dev/null 2>&1; sleep 1
  is "-at is scheduled too" "$(pending)" "2"

  # Posting to the same group drops the pending request.
  "$BIN" -message 'doctor: replaced' -group sched  >/dev/null 2>&1; sleep 1
  is "posting to the group replaces the scheduled one" "$(pending)" "1"

  "$BIN" -remove sched2 >/dev/null 2>&1; sleep 1
  is "-remove cancels a scheduled notification" "$(pending)" "0"

  clear_all
  "$BIN" -message 'doctor: x' -group s1 -in 1h >/dev/null 2>&1
  "$BIN" -message 'doctor: y' -group s2 -at '2027-03-04 05:06' >/dev/null 2>&1; sleep 1
  "$BIN" -remove ALL >/dev/null 2>&1; sleep 1
  is "-remove ALL cancels every scheduled notification" "$(pending)" "0"

  # -remove must not delete the notification the same invocation schedules.
  clear_all
  "$BIN" -message 'doctor: old' -group srace -in 1h >/dev/null 2>&1; sleep 1
  "$BIN" -remove srace -message 'doctor: new' -group srace -in 2h >/dev/null 2>&1; sleep 1
  is "-remove with a scheduled -message leaves one" "$(pending)" "1"
  is "-remove with a scheduled -message keeps the new one" \
     "$("$BIN" -list PENDING 2>/dev/null | tail -n +2 | head -1 | cut -f4)" "doctor: new"
  "$BIN" -remove ALL >/dev/null 2>&1; sleep 1
  clear_all

  # -remove combined with -message must not race.
  clear_all
  "$BIN" -message 'doctor: old' -group race >/dev/null 2>&1; sleep 1
  "$BIN" -remove race -message 'doctor: new' -group race >/dev/null 2>&1; sleep 1
  is "-remove with -message leaves one notification" "$(notifications)" "1"
  is "-remove with -message keeps the new one" "$(field 4)" "doctor: new"

  # piped stdin
  clear_all
  echo 'doctor: piped' | "$BIN" >/dev/null 2>&1; sleep 1
  is "piped stdin becomes the message" "$(field 4)" "doctor: piped"

  # Tabs and newlines must not break the table.
  clear_all
  "$BIN" -title "$(printf 'has\ta tab')" -message "$(printf 'and\na newline')" >/dev/null 2>&1
  sleep 1
  is "tabs and newlines do not corrupt -list" "$(notifications)" "1"

  # A deeplink with a scheme but no host must not be rejected as a bad
  # argument.
  clear_all
  for url in 'msteams:/l/chat/0/0' 'mailto:someone@example.com' 'tel:+15551234'; do
    "$BIN" -message 'doctor: deeplink' -open "$url" >/dev/null 2>&1 </dev/null
    if [ "$?" = "$TNExitBadArgument" ]; then
      bad "-open accepts $url" 'rejected as a bad argument'
    else
      ok "-open accepts $url"
    fi
    clear_all
  done

  # The documented first-character escape.
  clear_all
  "$BIN" -message '\[escaped' >/dev/null 2>&1; sleep 1
  is "a backslash-escaped first character is delivered" "$(field 4)" "[escaped"

  # -contentImage
  clear_all
  img="$(mktemp -t doctor).png"
  sips -s format png --resampleHeightWidth 128 128 \
    /System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/GenericApplicationIcon.icns \
    --out "$img" >/dev/null 2>&1
  err="$("$BIN" -message 'doctor: image' -contentImage "$img" 2>&1 >/dev/null)"
  sleep 1
  if [ -z "$err" ] && [ "$(notifications)" = "1" ]; then
    ok "-contentImage attaches a local image"
  else
    bad "-contentImage attaches a local image" "${err:-nothing delivered}"
  fi

  # UNNotificationAttachment moves the file it is given, so attaching must work
  # from a copy or it destroys the caller's image.
  clear_all
  keep="$(mktemp -t doctor-keep).png"
  sips -s format png --resampleHeightWidth 64 64 \
    /System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/GenericApplicationIcon.icns \
    --out "$keep" >/dev/null 2>&1
  "$BIN" -message 'doctor: keeps the file' -contentImage "$keep" >/dev/null 2>&1
  sleep 1
  if [ -f "$keep" ]; then ok "-contentImage does not delete the source file"
  else bad "-contentImage does not delete the source file" "the image was consumed by the attachment"; fi
  rm -f "$keep"

  # A missing image must warn but still deliver.
  clear_all
  err="$("$BIN" -message 'doctor: missing image' -contentImage /nope/none.png 2>&1 >/dev/null)"
  sleep 1
  if [ -n "$err" ] && [ "$(notifications)" = "1" ]; then
    ok "a missing -contentImage warns but still delivers"
  else
    bad "a missing -contentImage warns but still delivers" "stderr='$err' count=$(notifications)"
  fi
  rm -f "$img"

  # Removed options: warn, but do not break the notification.
  clear_all
  err="$("$BIN" -message 'doctor: sender' -sender com.apple.Terminal 2>&1 >/dev/null)"
  sleep 1
  case "$err" in
    *"-sender is no longer supported"*)
      if [ "$(notifications)" = "1" ]; then ok "-sender warns and still delivers"
      else bad "-sender warns and still delivers" "nothing delivered"; fi ;;
    *) bad "-sender warns and still delivers" "no warning on stderr" ;;
  esac

  clear_all
  err="$("$BIN" -message 'doctor: appicon' -appIcon /tmp/whatever.png 2>&1 >/dev/null)"
  sleep 1
  case "$err" in
    *"-appIcon is no longer supported"*)
      if [ "$(notifications)" = "1" ]; then ok "-appIcon warns and still delivers"
      else bad "-appIcon warns and still delivers" "nothing delivered"; fi ;;
    *) bad "-appIcon warns and still delivers" "no warning on stderr" ;;
  esac

  # Both spellings must deliver, even when the capability is unavailable and
  # the request falls back to an ordinary alert. Focus behavior needs a person.
  for option in -timeSensitive -ignoreDnD; do
    clear_all
    "$BIN" -message 'doctor: time sensitive' "$option" >/dev/null 2>&1; sleep 1
    is "$option still delivers" "$(notifications)" "1"
  done

  # -action / -reply timing out is fully automatable.
  clear_all
  is "-action times out with @TIMEOUT" \
     "$("$BIN" -message 'doctor: action timeout' -action 'Yes,No' -timeout 3 2>/dev/null)" "@TIMEOUT"
  exits "-action timing out exits 6" 6 -message 'doctor: t' -action Yes -timeout 3
  clear_all
  is "-reply times out with @TIMEOUT" \
     "$("$BIN" -message 'doctor: reply timeout' -reply 'type' -timeout 3 2>/dev/null)" "@TIMEOUT"

  # A notification nobody is listening to any more must not be left on screen
  # offering buttons that do nothing.
  clear_all
  "$BIN" -message 'doctor: timeout cleanup' -action Yes -timeout 3 >/dev/null 2>&1
  sleep 1
  is "a timed out notification is withdrawn" "$(notifications)" "0"

  for signal in INT TERM HUP; do
    clear_all
    "$BIN" -message "doctor: SIG$signal" -reply 'type' -timeout 60 >/dev/null 2>&1 &
    waiter=$!
    sleep 2
    kill "-$signal" "$waiter" 2>/dev/null
    wait "$waiter" 2>/dev/null
    sleep 1
    is "SIG$signal withdraws the notification" "$(notifications)" "0"
  done
  clear_all
fi

# =============================================================================
section "Checks that need you"

if [ "$CAN_DELIVER" = 0 ]; then
  skip "every interactive check" "notifications are not available in this session"
elif [ "$UNATTENDED" = 1 ]; then
  skip "every interactive check" "running with --unattended"
elif [ "$TTY_OK" = 0 ]; then
  skip "every interactive check" "no terminal available to prompt on"
else
  clear_all

  # -sound: only a person can tell whether it played.
  "$BIN" -message 'doctor: sound' -sound Glass >/dev/null 2>&1
  sleep 1
  if confirm "Did you HEAR a notification sound?"; then
    ok "-sound plays"
  else
    bad "-sound plays" "check System Settings > Notifications > sounds, and the volume"
  fi
  clear_all

  # -action: click a button.
  tell "A notification with Ship and Hold buttons is coming."
  tell "Hover it to reveal the buttons, then click Ship."
  answer="$("$BIN" -message 'doctor: click Ship' -action 'Ship,Hold' -timeout 60 2>/dev/null)"
  is "-action reports the clicked button" "$answer" "Ship"
  clear_all

  # -reply: type something.
  tell "Now a notification with a reply field."
  tell "Hover it, click Reply, type exactly:  hello"
  answer="$("$BIN" -message 'doctor: type hello' -reply 'type hello' -timeout 60 2>/dev/null)"
  is "-reply reports what was typed" "$answer" "hello"
  clear_all

  # Dismissal.
  tell "Now dismiss the next notification instead of clicking it"
  tell "(hover it and click the X, or swipe it away)."
  answer="$("$BIN" -message 'doctor: dismiss me' -action Ignore -timeout 60 2>/dev/null)"
  is "dismissing reports @CLOSED" "$answer" "@CLOSED"
  clear_all

  # -execute on click.
  marker="$(mktemp -t doctor-execute)"
  rm -f "$marker"
  tell "Click the body of the next notification (not a button)."
  "$BIN" -message 'doctor: click me' -execute "touch '$marker'" >/dev/null 2>&1
  printf "        waiting up to 60s for the click... "
  for _ in $(seq 1 60); do [ -f "$marker" ] && break; sleep 1; done
  printf "\n"
  if [ -f "$marker" ]; then ok "-execute runs the command on click"
  else bad "-execute runs the command on click" "the marker file never appeared"; fi
  rm -f "$marker"
  clear_all

  # -open on click.
  tell "One more: click the body of the next notification."
  tell "It should open example.com in your browser."
  "$BIN" -message 'doctor: opens a URL' -open 'https://example.com' >/dev/null 2>&1
  sleep 3
  if confirm "Did a browser open example.com?"; then ok "-open opens the URL on click"
  else bad "-open opens the URL on click" "clicking should have opened the browser"; fi
  clear_all

  # -activate on click.
  tell "Last one: click the body of the next notification."
  tell "It should bring Finder to the front."
  "$BIN" -message 'doctor: activates Finder' -activate 'com.apple.finder' >/dev/null 2>&1
  sleep 3
  if confirm "Did Finder come to the front?"; then ok "-activate brings the app forward"
  else bad "-activate brings the app forward" "clicking should have activated Finder"; fi
  clear_all
fi

# =============================================================================
printf "\n${B}Summary${Z}\n"
printf "  %s%d ok%s" "$G" "$PASS" "$Z"
[ "$SKIP" -gt 0 ] && printf ", %s%d skipped%s" "$Y" "$SKIP" "$Z"
[ "$FAIL" -gt 0 ] && printf ", %s%d problem(s)%s" "$R" "$FAIL" "$Z"
printf "\n"

if [ "$FAIL" -gt 0 ]; then
  printf "\n${R}Problems found:${Z}\n"
  for p in "${PROBLEMS[@]}"; do printf "  - %s\n" "$p"; done
  printf "\nStart with: %s -diagnose\n" "$BIN"
  exit 1
fi

# Skipped checks are not failures: a machine without a GUI session simply
# cannot run them.
if [ "$SKIP" -gt 0 ]; then
  printf "\nNo problems found. Some checks were skipped — see above.\n"
else
  printf "\nNo problems found.\n"
fi
exit 0
