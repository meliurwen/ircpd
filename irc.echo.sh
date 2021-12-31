#!/bin/sh

#set -x
#set -o pipefail

NAME="bottino"
CHAN="#test"

privmsg_send () {
    # If contains a space or starts with ":" char
    # then add a char ":" as a prefix
    if [ "${2#*" "}" != "$2" ]; then
        printf "PRIVMSG %s :%s\r\n" "$1" "$2"
    elif [ "${2#":"*}" != "$2" ]; then
        printf "PRIVMSG %s :%s\r\n" "$1" "$2"
    else
        printf "PRIVMSG %s %s\r\n" "$1" "$2"
    fi
}

tee /dev/stderr | {
	sleep 2
	printf "NICK %s\r\n" "${NAME}"
	printf "USER %s * * : %s\r\n" "cool_bot" "Very Cool Bot"
	sleep 5
	printf "JOIN %s\r\n" "${CHAN}"

	privmsg_send "${CHAN}" "Eccomiii! ^_^"

	while read -r line; do
		LINE="$(printf "%s\n" "${line}" | tr -d '\r')"
		case "$LINE" in
            "PING "*)
                # Server Pings
                printf "PONG %s\r\n" "$(printf "%s" "$LINE" | cut -d' ' -f2)"
                ;;
            ":"*)
                LINE_CLEAN="$(printf "%s" "${LINE}" | cut -c 2-)"
                SNDR_META="$(printf "%s" "${LINE_CLEAN}" | cut -d' ' -f1)"
                SNDR_META="$(printf "%s" "${SNDR_META}" | awk -F "[!~ @]" '{print $1 " " $3 " "  $4F}' )"
                SNDR_META_NICK="$(printf "%s" "${SNDR_META}" | cut -d' ' -f1 )"
                SNDR_META_USER="$(printf "%s" "${SNDR_META}" | cut -d' ' -f2 )"
                SNDR_META_HNAME="$(printf "%s" "${SNDR_META}" | cut -d' ' -f3 )"
                PAYLOAD="$(printf "%s" "${LINE_CLEAN}" | cut -d' ' -f2-)"
                PAYLOAD_CMD="$(printf "%s" "${PAYLOAD}" | cut -d' ' -f1)"
                case "$PAYLOAD_CMD" in
                    PRIVMSG )
                        PAYLOAD_DEST="$(printf "%s" "${PAYLOAD}" | cut -d' ' -f2)"
                        PAYLOAD_MSG="$(printf "%s" "${PAYLOAD}" | cut -d' ' -f3-)"
                        case "$PAYLOAD_DEST" in
                            "#"*)
                                printf "PRIVMSG %s %s\r\n" "$PAYLOAD_DEST" "$PAYLOAD_MSG"
                            ;;
                            *)
                                printf "PRIVMSG %s %s\r\n" "$SNDR_META_NICK" "$PAYLOAD_MSG"
                            ;;
                        esac
                    ;;
                    JOIN )
                        PAYLOAD_DEST="$(printf "%s" "${PAYLOAD}" | cut -d' ' -f2)"
                        privmsg_send "$PAYLOAD_DEST" "Howdy $SNDR_META_NICK OwO!"
                        sleep 2
                        privmsg_send "$PAYLOAD_DEST" "We are spread across different timezones and we'll reach you asap"
                        sleep 2
                        privmsg_send "$PAYLOAD_DEST" "In the meantime write few lines about you ^_^"
                        sleep 2
                        privmsg_send "$PAYLOAD_DEST" "Enjoy!"
                        sleep 2
                        privmsg_send "$PAYLOAD_DEST" ":UwU"
                        sleep 2
                        privmsg_send "$PAYLOAD_DEST" "OwO:"
                    ;;
                    *)
                    ;;
                esac
            ;;
            *)
            ;;
		esac
	done
} | tee /dev/stderr

exit 0
