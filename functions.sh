#!/usr/bin/env bash

# ==============
#    Functions
# ==============

# Telegram functions
# upload_file
upload_file() {
  local FILE="$1"
  local CAPTION="${2:-}"

  if ! [ -f $FILE ]; then
    error "file $FILE doesn't exist"
  fi

  chmod 777 "$FILE"

  curl -s -F "document=@${FILE}" \
    -F "chat_id=${TG_CHAT_ID}" \
    -F "caption=${CAPTION}" \
    -F "parse_mode=markdown" \
    -F "disable_web_page_preview=true" \
    "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendDocument"
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

# Live Logging for Compilation (Edit Message)
live_log() {
  local MSG_ID=""
  local LINE_COUNT=0
  local UPDATE_LIMIT=15 # Update every 15 compilation steps to avoid rate limits
  local RESP
  local CLEAN_LINE

  # Initial Progress Message
  RESP=$(curl -s -X POST "https://api.telegram.org/bot$TG_BOT_TOKEN/sendMessage" \
    -d "chat_id=$TG_CHAT_ID" \
    -d "parse_mode=markdown" \
    -d "text=🔨 *Compilation Progress:* Starting...")
  
  # Extract message_id from JSON response
  MSG_ID=$(echo "$RESP" | grep -o '"message_id":[0-9]*' | cut -d: -f2)

  while read -r line; do
    echo "$line" # Print to build.log
    # Filter for compilation steps
    if [[ "$line" =~ ^[\ ]*(CC|LD|AR|AS)[\ ]+ ]]; then
       ((LINE_COUNT++))
       # Update the existing message every N steps
       if (( LINE_COUNT % UPDATE_LIMIT == 0 )); then
          CLEAN_LINE=$(echo "$line" | sed 's/[[:space:]]\+/ /g' | sed 's/\*/\\*/g') # Escape markdown
          curl -s -X POST "https://api.telegram.org/bot$TG_BOT_TOKEN/editMessageText" \
            -d "chat_id=$TG_CHAT_ID" \
            -d "message_id=$MSG_ID" \
            -d "parse_mode=markdown" \
            -d "text=🔨 *Compiling:* \`[$LINE_COUNT]\` \`$CLEAN_LINE\`" > /dev/null
       fi
    fi
  done

  # Final status update for the same message
  curl -s -X POST "https://api.telegram.org/bot$TG_BOT_TOKEN/editMessageText" \
    -d "chat_id=$TG_CHAT_ID" \
    -d "message_id=$MSG_ID" \
    -d "parse_mode=markdown" \
    -d "text=✅ *Compilation Finished:* \`$LINE_COUNT\` steps completed." > /dev/null
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
❌ *Build Failed!*
━━━━━━━━━━━━━━━━━━━━
⚠️ *Error:* \`$*\`
━━━━━━━━━━━━━━━━━━━━
EOF
  )
  echo -e "[ERROR] $*"
  send_msg "$err_txt"
  upload_file "$WORKDIR/build.log" "📄 *Build Log (Failure)*"
  exit 1
}