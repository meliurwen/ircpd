#!/bin/sh

set -e

while [ $# -gt 0 ]; do
    case "$1" in
        --config )
            shift
            if [ -r "$1" ]; then
                printf "Loading \"%s\" config file...\n" "$1"
                . "$1"
            else
                printf "Config file \"%s\" does not exist or no read permissions. Terminating...\n" "$1"
                exit 1
            fi
        ;;
        --nick )
            shift
            NICK="$1"
        ;;
        --addr )
            shift
            IRCD_ADDR="$1"
        ;;
        --port )
            shift
            IRCD_PORT="$1"
        ;;
        --chan )
            shift
            CHAN="$1"
        ;;
        --tls )
            TLS="true"
        ;;
        * )
            printf "Unrecognized argument: %s\n" "$1"
            exit 1
        ;;
    esac
    shift
done

NICK="${NICK:-testbot}"
USERNAME="${USERNAME:-usertestbot}"
REALNAME="${REALNAME:-Test Bot}"

IRCD_ADDR="${IRCD_ADDR:-127.0.0.1}"
IRCD_PORT="${IRCD_PORT:-6667}"
CHAN="${CHAN:-}"

TLS="${TLS:-false}"

# Value: 1<=interval<=1023
# If value is <= 0 then do not actively ping; this way the bot connection relies
# solely on the pings sent from the server
PING_INTERVAL=${PING_INTERVAL:-30}

NPIPE_IN=${NPIPE_IN:-./botin.fifo}
NPIPE_OUT=${NPIPE_OUT:-./botout.fifo}

thrd_connection () {
    # <IRCD_ADDR> <IRCD_PORT> <PID_SELF>
    tail -f "$NPIPE_OUT" | \
        nc -v "$1" "$2" > \
            "$NPIPE_IN" \
            || printf "nc or tail process crashed!\n"
    printf "Sending termination signal to parent process (PID %s)...\n" "$3"
    kill "$3"
    printf "Exiting \"thrd_connection\" with error...\n"
    exit 1
}

thrd_openssl_connection () {
    # <IRCD_ADDR> <IRCD_PORT> <PID_SELF>
    tail -f "$NPIPE_OUT" | \
        openssl s_client -connect "$1":"$2" > \
            "$NPIPE_IN" \
            || printf "openssl or tail process crashed!\n"
    printf "Sending termination signal to parent process (PID %s)...\n" "$3"
    kill "$3"
    printf "Exiting \"thrd_connection\" with error...\n"
    exit 1
}

thrd_ctrl () {
    # <IRCD_ADDR> <PING_INTERVAL> <PID_PARENT_SCRIPT>
    thrd_ctrl_counter=0
    while true; do
        if ! kill -0 "$3" 2>/dev/null; then 
            printf "Parent process died, I'm going to die too...\n"
            exit 0
        fi
        if [ $((thrd_ctrl_counter%$2)) -eq 0 ] ; then
            printf "PING %s\r\n" "$1" > "$NPIPE_OUT"
        fi
        sleep 1
        thrd_ctrl_counter=$((thrd_ctrl_counter + 1))
        if [ $thrd_ctrl_counter -ge 1023 ]; then
            thrd_ctrl_counter=0
        fi
    done
}

term_process () {
    if kill -0 "$PID_NC" 2>/dev/null; then 
        printf "Sending QUIT message...\n"
        printf "QUIT :I have decided that I want to die.\r\n" > "$NPIPE_OUT"
        sleep 1 # Give time to nc to deliver the QUIT message
        printf "Killing child process \"thrd_connection\" (PID %s) and its own children (%s)...\n" "$PID_NC" "$PID_NC_CHILDREN"
        for i in $PID_NC_CHILDREN; do
            printf "Killing PID %s...\n" "$i"
            kill "$i"
        done
        printf "Killing PID %s...\n" "$PID_NC"
        kill "$PID_NC"
    else
        printf "Child process \"thrd_connection\" (PID %s) died, not sending QUIT message...\n" "$PID_NC"
    fi
    if kill -0 "$PID_CTRL" 2>/dev/null; then
        printf "Killing child process \"thrd_ctrl\" (PID %s)...\n" "$PID_CTRL"
        kill "$PID_CTRL"
    fi
    printf "Removing created FIFOs...\n"
    rm "$NPIPE_OUT" "$NPIPE_IN"
    printf "Terminating the bot...\n"
    exit 0
}

trap_ctrlc () {
    printf "Termination signal by the user (CTLR+C) detected...\n"
    term_process
}

trap_sigterm () {
    printf "Termination signal detected...\n"
    term_process
}

privmsg_send () {
    PMSG_DST="$1"; PMSG_TXT="$2"; PMSG_RAW="$3"
    # If it is not raw process it
    if [ "$PMSG_RAW" != "1" ]; then
        PMSG_TXT=":$PMSG_TXT"
    fi

    # Primitive rate limiter: if the delta time between the last sent message
    # and the actual pending one is less than 2000ms then wait until 2000ms
    # is reached
    LASTMSG_DELTA=$(( ( $($GNU_DATE_CMD '+%s%N') / 1000000) - LASTMSG ))
    if [ $LASTMSG_DELTA -lt 2000 ]; then
        TMP=$(( 2000 - LASTMSG_DELTA ))
        sleep $((TMP/1000)).$((TMP%1000))
    fi
    printf "PRIVMSG %s %s\r\n" "$PMSG_DST" "$PMSG_TXT" > "$NPIPE_OUT"
    LASTMSG=$(( $($GNU_DATE_CMD '+%s%N') / 1000000))
    printf "PRIVMSG %s %s\r\n" "$PMSG_DST" "$PMSG_TXT"
    unset PMSG_DST PMSG_TXT PMSG_RAW
}

login_procedure () {
    # <NICK> <USERNAME> <REALNAME>
    printf "NICK %s\r\n" "$1" > "$NPIPE_OUT"
    printf "USER %s * * :%s\r\n" "$2" "$3" > "$NPIPE_OUT"
}

handle_failed_conn_reg () {
    printf "I'm unable to handle this failed connection registration. Terminating...\n"
    term_process
}

do_perform () {
    printf "JOIN %s\r\n" "${CHAN}" > "$NPIPE_OUT"
    unset IRCBOT_PERFORM
}

do_greet () {
    # <$PAYLOAD_DEST> <$SNDR_META_NICK>
    if [ "$2" != "$NICK" ]; then
        privmsg_send "$1" "Howdy $2 OwO!"
        privmsg_send "$1" "We are spread across different timezones and we'll reach you asap"
        privmsg_send "$1" "In the meantime write few lines about you ^_^"
        privmsg_send "$1" "Enjoy!"
        privmsg_send "$1" ":UwU"
        privmsg_send "$1" "OwO:"
    fi
}

msg_cmd_colon () {
    # <LINE> <MSG_CMD>
    SNDR_META="$(printf "%s" "${2}" | cut -c 2- | awk -F "[!~ @]" '{print $1 " " $3 " "  $4F}' )"
    SNDR_META_NICK="$(printf "%s" "${SNDR_META}" | cut -d' ' -f1 )"
    SNDR_META_USER="$(printf "%s" "${SNDR_META}" | cut -d' ' -f2 )"
    SNDR_META_HNAME="$(printf "%s" "${SNDR_META}" | cut -d' ' -f3 )"
    PAYLOAD="$(printf "%s" "${1}" | cut -d' ' -f2-)"
    PAYLOAD_CMD="$(printf "%s" "${PAYLOAD}" | cut -d' ' -f1)"
    case "$PAYLOAD_CMD" in
        PRIVMSG )
            PAYLOAD_DEST="$(printf "%s" "${PAYLOAD}" | cut -d' ' -f2)"
            PAYLOAD_MSG="$(printf "%s" "${PAYLOAD}" | cut -d' ' -f3-)"
            case "$PAYLOAD_DEST" in
                "#"*)
                    privmsg_send "$PAYLOAD_DEST" "$PAYLOAD_MSG" 1
                ;;
                *)
                    privmsg_send "$SNDR_META_NICK" "$PAYLOAD_MSG" 1
                ;;
            esac
            unset PAYLOAD_DEST PAYLOAD_MSG
        ;;
        JOIN )
            PAYLOAD_DEST="$(printf "%s" "${PAYLOAD}" | cut -d' ' -f2)"
            do_greet "$PAYLOAD_DEST" "$SNDR_META_NICK"
            unset PAYLOAD_DEST
        ;;
        KICK )
            PAYLOAD_DEST="$(printf "%s" "${PAYLOAD}" | cut -d' ' -f2)"
            PAYLOAD_KICK_RECIPIENT="$(printf "%s" "${PAYLOAD}" | cut -d' ' -f3)"
            printf "KICK from channel %s to %s by %s (%s)\n" "$PAYLOAD_DEST" "$PAYLOAD_KICK_RECIPIENT" "$SNDR_META_NICK" "$SNDR_META_USER@$SNDR_META_HNAME"
            unset PAYLOAD_DEST PAYLOAD_KICK_RECIPIENT
        ;;
        INVITE )
            PAYLOAD_DEST="$(printf "%s" "${PAYLOAD}" | cut -d' ' -f2)"
            PAYLOAD_INVITE_RECIPIENT="$(printf "%s" "${PAYLOAD}" | cut -d' ' -f3)"
            PAYLOAD_INVITE_RECIPIENT="${PAYLOAD_INVITE_RECIPIENT#:}"
            printf "INVITE to %s to join channel %s by %s (%s)\n" "$PAYLOAD_DEST" "$PAYLOAD_INVITE_RECIPIENT" "$SNDR_META_NICK" "$SNDR_META_USER@$SNDR_META_HNAME"
            unset PAYLOAD_DEST PAYLOAD_INVITE_RECIPIENT
        ;;
        MODE )
            PAYLOAD_DEST="$(printf "%s" "${PAYLOAD}" | cut -d' ' -f2)"
            PAYLOAD_MODE_TYPE="$(printf "%s" "${PAYLOAD}" | cut -d' ' -f3)"
            case "$PAYLOAD_DEST" in
                [\&#+!]* ) # It's a channel
                    PAYLOAD_MODE_B_ON="$(printf "%s" "${PAYLOAD}" | cut -d' ' -f4)"
                    printf "MODE %s from channel %s to %s by %s (%s)\n" "$PAYLOAD_MODE_TYPE" "$PAYLOAD_DEST" "$PAYLOAD_MODE_B_ON" "$SNDR_META_NICK" "$SNDR_META_USER@$SNDR_META_HNAME"
                    unset PAYLOAD_MODE_B_ON
                ;;
                * ) # Assue it's a nickname (validating this it's a pain)
                    printf "MODE %s to nick %s by %s\n" "${PAYLOAD_MODE_TYPE#:}" "$PAYLOAD_DEST" "$SNDR_META_NICK"
                    unset PAYLOAD_MODE_B_ON
                ;;
            esac
            unset PAYLOAD_DEST PAYLOAD_MODE_TYPE
        ;;
        [0-9][0-9][0-9] )
            case "$PAYLOAD_CMD" in
                001 ) # Successfull connection registration
                    IRCBOT_CONN_REG="ok"
                    printf "Connection registration succeeded!\n"
                ;;
                004 )
                    [ -n "$IRCBOT_PERFORM" ] && do_perform
                    # If PING_INTERVAL is <= 0 do not even spawn the process;
                    # this way we avoid resources waste and division by 0.
                    if [ $PING_INTERVAL -ge 1 ]; then
                        thrd_ctrl "${IRCD_ADDR}" $PING_INTERVAL $PID_SELF &
                        PID_CTRL=$!
                    fi
                    :
                ;;
                474 )
                    PAYLOAD_CHAN="$(printf "%s" "${PAYLOAD}" | cut -d' ' -f3)"
                    printf "ERROR %s, BANNED FROM CHANNEL %s\n" "$PAYLOAD_CMD" "$PAYLOAD_CHAN"
                ;;
                *)
                    :
                ;;
            esac
        ;;
        *)
        ;;
    esac
}

# We need milliseconds and only the GNU implementation of `date` can give that;
# the BSD implementation does not, so we need to check if the appropriate one
# is installed and be sure to use the right command
if date --version >/dev/null 2>&1 ; then
    printf "Using GNU date"
    GNU_DATE_CMD="date"
elif gdate --version >/dev/null 2>&1 ; then
    GNU_DATE_CMD="gdate"
else
    printf "GNU date not found. Install GNU coreutils. Terminating..."
    exit 1
fi

trap "trap_ctrlc" 2
trap "trap_sigterm" 15

mkfifo "$NPIPE_OUT" 2> /dev/null || printf "fifo already present\n"
mkfifo "$NPIPE_IN" 2> /dev/null || printf "fifo already present\n"

PID_SELF=$$

if [ "$TLS" = "true" ]; then
    thrd_openssl_connection "$IRCD_ADDR" "$IRCD_PORT" "$PID_SELF" &
else
    thrd_connection "$IRCD_ADDR" "$IRCD_PORT" "$PID_SELF" &
fi
PID_NC=$!
# Get list of children PIDs, transform newlines in whitespaces and then trim
PID_NC_CHILDREN="$(pgrep -P $PID_NC | tr '\n' ' ' | awk '{$1=$1;print}')"

IRCBOT_CONN_REG="ok"
IRCBOT_PERFORM="1"
LASTMSG="0"

login_procedure "$NICK" "$USERNAME" "$REALNAME"

while read -r line; do
    LINE="$(printf "%s\n" "${line}" | tr -d '\r')"
    printf "%s\n" "$LINE"
    MSG_CMD="$(printf "%s" "${LINE}" | cut -d' ' -f1)"

    [ "$IRCBOT_CONN_REG" != "ok" ] && handle_failed_conn_reg

    case "$MSG_CMD" in
        PING )
            # Server Pings
            printf "PONG%s\r\n" "${LINE#PING}" > "$NPIPE_OUT"
            printf "PONG%s\r\n" "${LINE#PING}"
        ;;
        ":"* )
            msg_cmd_colon "${LINE}" "${MSG_CMD}"
        ;;
        *)
        ;;
    esac
done < "$NPIPE_IN"
