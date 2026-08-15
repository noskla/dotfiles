#!/bin/sh
eval $(dbus-launch --sh-syntax)
export DBUS_SESSION_BUS_ADDRESS
eval $(gnome-keyring-daemon --start --components=secrets,ssh,pkcs11)
export SSH_AUTH_SOCK

exec fvwm3

