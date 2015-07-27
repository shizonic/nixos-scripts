#!/usr/bin/env bash

source $(dirname ${BASH_SOURCE[0]})/nix-utils.sh

CONFIG_DIR=

COMMAND="switch"

usage() {
    cat <<EOS

    $(help_synopsis "${BASH_SOURCE[0]}" "[-h] [-c <command>] -w <working directory> [-- args...]")

        -c <command>    Command for nixos-rebuild. See 'man nixos-rebuild'
        -w <path>       Path to your configuration git directory
        -n              DON'T include hostname in tag name
        -t <tagname>    Custom tag name
        -h              Show this help and exit

        This command helps you rebuilding your system and keeping track
        of the system generation in the git directory where your
        configuration.nix lives. It generates a tag for each sucessfull
        build of a system. So everytime you rebuild your system, this
        script creates a tag for you, so you can revert your
        configuration.nix to the generation state.

        Example usage:

            # To rebuild the system with "nixos-rebuild switch" (by -c
            # switch), tag in /home/me/config and include the hostname
            # in the tag as well (helpful if your configuration is
            # shared between hosts).
            # Verbosity is on here.
            nix-script -v switch -c switch -w /home/me/config -n

        Everything after a double dash (--) will be passed to nixos-rebuild as
        additional parameters. For example:

            nix-script switch -c switch -- -I nixpkgs=/home/user/pkgs

        can be used to use your local clone of the nixpkgs repository.

$(help_end)
EOS
}

COMMAND=
ARGS=
WD=
TAG_NAME=
HOSTNAME="$(hostname)"

while getopts "c:w:t:nh" OPTION
do
    case $OPTION in
        c)
            COMMAND=$OPTARG
            dbg "COMMAND = $COMMAND"
            ;;
        w)
            WD=$OPTARG
            dbg "WD = $WD"
            ;;
        t)
            TAG_NAME=$OPTARG
            dbg "TAG_NAME = $TAG_NAME"
            ;;

        n)
            HOSTNAME=""
            dbg "HOSTNAME disabled"
            ;;

        h)
            usage
            exit 1
            ;;
    esac
done

ARGS=$(echo $* | sed -r 's/(.*)(\-\-(.*)|$)/\2/')
dbg "ARGS = $ARGS"

[[ -z "$WD" ]] && \
    stderr "No configuration git directory." && \
    stderr "Won't do anything" && exit 1

[[ ! -d "$WD" ]]        && stderr "No directory: $WD" && exit 1
[[ -z "$COMMAND" ]]     && COMMAND="switch"

explain sudo nixos-rebuild $COMMAND $ARGS
REBUILD_EXIT=$?

if [[ $REBUILD_EXIT -eq 0 ]]
then
    LASTGEN=$(current_system_generation)
    sudo -k

    stdout "sudo -k succeeded"
    stdout "Last generation was: $LASTGEN"

    if [[ -z "$TAG_NAME" ]]
    then
        if [[ -z "$HOSTNAME" ]]; then TAG_NAME="nixos-$LASTGEN-$COMMAND"
        else TAG_NAME="nixos-$HOSTNAME-$LASTGEN-$COMMAND"
        fi
    fi

    __git "$WD" tag -a "$TAG_NAME"

else
    stderr "Switching failed. Won't executing any further commands."
    exit $REBUILD_EXIT
fi

