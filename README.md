# IRCPd

IRC POSIX daemon, a multi-threaded daemon, written in pure shell which goals
are maximum portability, minimalism and strict compliancy to the POSIX
standards.

Currently only selected parts of RFC1259, RFC2812 and RFC7194 are implemented.

## Requirements

Any POSIX compliant system, `netcat` and `GNU date` are the only requirements.

Additionally, if TLS is used, then `openssl` is also required.
