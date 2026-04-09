#!/usr/bin/env bash

# ==============
#    Functions
# ==============

# Telegram functions
# upload_file
upload_file() {
  local FILE="$1"
  local CAPTION="${2:-}"
  local RESP
  local FILE_SIZE

  if ! [ -f "$FILE" ]; then
    error "file $FILE doesn't exist"
  fi

  FILE_SIZE=$(stat -c%s "$FILE")
  # Telegram Bot API limit is 50MB (52428800 bytes)
  if [ "$FILE_SIZE" -gt 52428800 ]; then
    log "⚠️ File $(basename "$FILE") is too large for Telegram Bot API ($((FILE_SIZE/1024/1024))MB > 50MB). Skipping Telegram upload."
    log "🔗 You can find it in the GitHub Release/Artifacts."
    return 0
  fi

  chmod 777 "$FILE"

  RESP=$(curl -s -w "\n%{http_code}" -F "document=@${FILE}" \
    -F "chat_id=${TG_CHAT_ID}" \
    -F "caption=${CAPTION}" \
    -F "parse_mode=markdown" \
    -F "disable_web_page_preview=true" \
    "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendDocument")
  
  local HTTP_CODE=$(echo "$RESP" | tail -n 1)
  local BODY=$(echo "$RESP" | head -n -1)

  if [ "$HTTP_CODE" -ne 200 ]; then
    log "❌ Telegram upload failed for $(basename "$FILE") with code $HTTP_CODE"
    log "📄 Response: $BODY"
  else
    echo "✅ Successfully uploaded $(basename "$FILE") to Telegram"
  fi
}

# send_msg
send_msg() {
  local MESSAGE="$1"
  curl -s -X POST "https://api.telegram.org/bot$TG_BOT_TOKEN/sendMessage" \
    -d "chat_id=$TG_CHAT_ID" \
    -d "disable_web_page_preview=true" \
    -d "parse_mode=markdown" \
    -d "text=$MESSAGE"
}

# step_msg
step_msg() {
  local STEP="$1"
  local DETAILS="${2:-}"
  local MSG
  MSG="🔷 *Step:* \`$STEP\`"
  if [ -n "$DETAILS" ]; then
    MSG="$MSG
🔹 *Details:* \`$DETAILS\`"
  fi
  send_msg "$MSG"
}

# Live Logging for Compilation (Edit Message)
live_log() {
  local MSG_ID=""
  local LINE_COUNT=0
  local UPDATE_LIMIT=20 # Update every 20 compilation steps to avoid rate limits
  local RESP
  local CLEAN_LINE
  local PROGRESS_BAR
  local PERCENTAGE
  local SPINNER=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
  local SPIN_IDX=0

  # Initial Progress Message
  RESP=$(curl -s -X POST "https://api.telegram.org/bot$TG_BOT_TOKEN/sendMessage" \
    -d "chat_id=$TG_CHAT_ID" \
    -d "parse_mode=markdown" \
    -d "text=💎 *Compiling SKY-OSS Kernel...*
━━━━━━━━━━━━━━━━━━━━
🔄 *Status:* \`Initializing...\`
━━━━━━━━━━━━━━━━━━━━")
  
  # Extract message_id from JSON response
  MSG_ID=$(echo "$RESP" | grep -o '"message_id":[0-9]*' | cut -d: -f2)

  while read -r line; do
    echo "$line" # Print to build.log
    # Filter for compilation steps
    if [[ "$line" =~ ^[\ ]*(CC|LD|AR|AS)[\ ]+ ]]; then
       ((LINE_COUNT++))
       # Update the existing message every N steps
       if (( LINE_COUNT % UPDATE_LIMIT == 0 )); then
          CLEAN_LINE=$(echo "$line" | sed 's/[[:space:]]\+/ /g' | sed 's/\*/\\*/g' | cut -d' ' -f2-) # Escape markdown and remove CC/LD
          # Simple progress bar logic (assuming ~1500-2000 steps for a full build, this is just visual)
          PROGRESS_BAR="[$(printf '%0.s#' $(seq 1 $((LINE_COUNT / 100))))$(printf '%0.s-' $(seq 1 $((20 - LINE_COUNT / 100))))]"
          SPIN_IDX=$(( (SPIN_IDX + 1) % 10 ))
          
          curl -s -X POST "https://api.telegram.org/bot$TG_BOT_TOKEN/editMessageText" \
            -d "chat_id=$TG_CHAT_ID" \
            -d "message_id=$MSG_ID" \
            -d "parse_mode=markdown" \
            -d "text=🔨 *Compiling:* \`${SPINNER[$SPIN_IDX]}\`
━━━━━━━━━━━━━━━━━━━━
🔢 *Step:* \`$LINE_COUNT\`
\`$PROGRESS_BAR\`
📍 *Current:* \`$CLEAN_LINE\`
━━━━━━━━━━━━━━━━━━━━" > /dev/null
       fi
    fi
  done

  # Final status update for the same message
  curl -s -X POST "https://api.telegram.org/bot$TG_BOT_TOKEN/editMessageText" \
    -d "chat_id=$TG_CHAT_ID" \
    -d "message_id=$MSG_ID" \
    -d "parse_mode=markdown" \
    -d "text=✅ *Compilation Finished!*
━━━━━━━━━━━━━━━━━━━━
📦 *Total Steps:* \`$LINE_COUNT\`
✨ *Build Status:* \`Success\`
━━━━━━━━━━━━━━━━━━━━" > /dev/null
}

# KernelSU-related functions
install_ksu() {
  local REPO="$1"
  local REF="$2"
  local URL

  if [ -z "$REPO" ] || [ -z "$REF" ]; then
    echo "Usage: install_ksu <user/repo> <ref>"
    exit 1
  fi

  URL="https://raw.githubusercontent.com/$REPO/$REF/kernel/setup.sh"
  log "Installing KernelSU from $REPO | $REF"
  curl -LSs "$URL" | bash -s "$REF"
}

# ksu_included() function
# Type: bool
# Returns true when any KernelSU variant is selected (kernelsu, next)
ksu_included() {
  [[ "$KSU" == "kernelsu" || "$KSU" == "next" ]]
  return $?
}

# susfs_included() function
# Type: bool
susfs_included() {
  # Return True jika input KSU_SUSFS adalah "true"
  # Ini digunakan oleh build.sh untuk memutuskan apakah akan clone SUSFS (Standard/Manual Fix)
  # atau membiarkan VorteXSU menangani patchingnya sendiri.
  [ "$KSU_SUSFS" == "true" ]
  return $?
}

# simplify_gh_url <github-repository-url>
simplify_gh_url() {
  local URL="$1"
  echo "$URL" | sed "s|https://github.com/||g" | sed "s|.git||g"
}

# Kernel scripts function
config() {
  # Modify output .config if it exists (post-make), else source defconfig
  if [ -f "$OUTDIR/.config" ]; then
    $KSRC/scripts/config --file $OUTDIR/.config $@
  else
    $KSRC/scripts/config --file $DEFCONFIG_FILE $@
  fi
}

# Logging function
log() {
  echo -e "[LOG] $*"
  send_msg "⏺️ *LOG:* $*"
}

error() {
  local err_txt
  err_txt=$(
    cat << EOF
🛑 *Build Interrupted!*
━━━━━━━━━━━━━━━━━━━━
⚠️ *Error Detail:*
\`$*\`

🔍 *Check the logs below for more details.*
━━━━━━━━━━━━━━━━━━━━
EOF
  )
  echo -e "[ERROR] $*"
  send_msg "$err_txt"
  upload_file "$WORKDIR/build.log" "📄 *Failure Analysis (Build Log)*"
  exit 1
}