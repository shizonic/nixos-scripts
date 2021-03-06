#!/usr/bin/env bash

source $(dirname ${BASH_SOURCE[0]})/nix-utils.sh

CONFIG_DIR=

COMMAND="switch"

usage() {
    cat <<EOS

    $(help_synopsis "${BASH_SOURCE[0]}" \
                    "[-h] [-q] [-c <command>] [-w <working directory>]")

        -c <command>    Command for nixos-rebuild.
                        See 'man nixos-rebuild' (default: switch)

        -w <path>       Path to your configuration git directory
                        (default: '$RC_CONFIG')

        -n              DON'T include hostname in tag name

        -t <tagname>    Custom tag name

        -C              Append channel generation in tag (<tag>-channel-<gen>-<sha1>)
                        Expl:
                            <tag> : nixos-<hostname>
                            <gen> : Number of the generation
                            <sha1>: SHA1 (abbrev) of the commit of the channel in nixpkgs

        -p [<pkgs>]     Generate the switch tag in the nixpkgs at <pkgs>
                        as well.  (default: '$RC_NIXPKGS')
                        (Warning: deprecated
                            This flag is deprecated as tagging with the channel
                            commit hash is now default
                        )

        -r [<remote>]   Update the <remote> in the <pkgs> before tagging.
                        Multiple possible, seperate with spaces.
                        Does nothing if -p is not passed.
                        (nixpkgs default: '$RC_NIXPKGS', remote default: '$RC_SWITCH_UPSTREAM_NIXPKGS_REMOTE_NAME')

        -f <tag-flags>  Flags for git-tag (see 'git tag --help')
                        (default: '$RC_SWITCH_DEFAULT_TAG_FLAGS')

        -b              Do not call nixos-rebuild at all.

        -q              Don't pass -Q to nixos-rebuild

        -s <pkgs>       Use these nixpkgs clone instead of channels

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

        This command does not generate a tag in the configuration if
        the command is "build". A tag in the nixpkgs clone can be
        generated, though.

$(help_rcvars                                                       \
    "RC_CONFIG  - Path of your system configuration (git) directory"\
    "RC_NIXPKGS - Path of your nixpkgs clone"                       \
    "RC_SWITCH_DEFAULT_TAG_FLAGS            - Default git-tag flags for tagging in system configuration (git) directory"\
    "RC_SWITCH_DEFAULT_TAG_FLAGS_NIXPKGS    - Default git-tag flags for tagging in nixpkgs"\
    "RC_SWITCH_UPSTREAM_NIXPKGS_REMOTE_NAME - Default git-remote name for the upstream nixpkgs"
)

$(help_end "${BASH_SOURCE[0]}")
EOS
}

COMMAND=switch
ARGS=
WD=$RC_CONFIG
TAG_NAME=
APPEND_CHANNEL_GEN=
HOSTNAME="$(hostname)"
TAG_NIXPKGS=0
NIXPKGS=$RC_NIXPKGS
TAG_FLAGS="$RC_SWITCH_DEFAULT_TAG_FLAGS"
TAG_FLAGS_NIXPKGS="$RC_SWITCH_DEFAULT_TAG_FLAGS_NIXPKGS"
DO_UPSTREAM_UPDATE=0
UPSTREAM_REMOTE="$RC_SWITCH_UPSTREAM_NIXPKGS_REMOTE_NAME"
DONT_BUILD=
QUIET=1
USE_ALTERNATIVE_SOURCE_NIXPKGS=0

while getopts "c:w:t:Cnbp:f:qs:r:h" OPTION
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

        C)
            APPEND_CHANNEL_GEN=1
            dbg "APPEND_CHANNEL_GEN = $APPEND_CHANNEL_GEN"
            ;;

        n)
            HOSTNAME=""
            dbg "HOSTNAME = $HOSTNAME"
            ;;

        p)
            if [[ ! -z "$OPTARG" ]]
            then
                NIXPKGS=$OPTARG
            fi
            TAG_NIXPKGS=1
            dbg "TAG_NIXPKGS = $TAG_NIXPKGS"
            ;;

        f)
            TAG_FLAGS=$OPTARG
            dbg "TAG_FLAGS = $TAG_FLAGS"
            ;;

        b)
            DONT_BUILD=1
            dbg "DONT_BUILD = $DONT_BUILD"
            ;;

        q)
            QUIET=0
            dbg "QUIET = $QUIET"
            ;;

        s)
            USE_ALTERNATIVE_SOURCE_NIXPKGS=1
            ALTERNATIVE_SOURCE_NIXPKGS="$OPTARG"
            dbg "USE_ALTERNATIVE_SOURCE_NIXPKGS = $USE_ALTERNATIVE_SOURCE_NIXPKGS"
            dbg "ALTERNATIVE_SOURCE_NIXPKGS     = $ALTERNATIVE_SOURCE_NIXPKGS"
            ;;

        r)
            DO_UPSTREAM_UPDATE=1
            if [[ -z "$OPTARG" ]]; then
                dbg "Using default upstream"
            else
                UPSTREAM_REMOTE="$OPTARG"
            fi
            dbg "DO_UPSTREAM_UPDATE = $DO_UPSTREAM_UPDATE"
            dbg "UPSTREAM_REMOTE = '$UPSTREAM_REMOTE'"
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

[[ ! -d "$WD" ]] && stderr "No directory: $WD" && exit 1

[[ "$COMMAND" != "switch" ]] && [[ $APPEND_CHANNEL_GEN == 1 ]] && {
    stderr "Cannot append channel generation if non-switch build,"
    stderr "as this is currently not supported."
    exit 1
}

TAG_TARGET=$(__quiet__ __git "$WD" rev-parse HEAD)
stdout "Tag in config will be generated at '$TAG_TARGET'"

if [[ -z "$DONT_BUILD" ]]
then
    __q="-Q"
    [[ $QUIET -eq 0 ]] && __q=""

    __altnixpkgs=""
    [[ $USE_ALTERNATIVE_SOURCE_NIXPKGS -eq 1 ]] && \
        [[ -d "$ALTERNATIVE_SOURCE_NIXPKGS" ]] && \
        __altnixpkgs="-I nixpkgs=$ALTERNATIVE_SOURCE_NIXPKGS"

    explain sudo nixos-rebuild $__q $COMMAND $ARGS $__altnixpkgs
    REBUILD_EXIT=$?
else
    stdout "Do not call nixos-rebuild"
    REBUILD_EXIT=0
fi

[[ ! $REBUILD_EXIT -eq 0 ]] && \
    stderr "Switching failed. Won't executing any further commands." && \
    exit $REBUILD_EXIT

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

if [[ $APPEND_CHANNEL_GEN -eq 1 ]]; then
    dbg "Appending channel generation to tag name"
    commit=$(nixos-version | sed -r 's,(.*)\.(.*)\ (.*),\2,')
    TAG_NAME="${TAG_NAME}-channel-$(current_channel_generation)-${commit}"
    dbg "TAG_NAME = $TAG_NAME"
else
    dbg "Not appending channel generation to tag name"
fi

if [[ "$COMMAND" =~ "build" ]]
then
    stdout "Command is 'build'. Not generating config tag"
else
    __git "$WD" tag $TAG_FLAGS "$TAG_NAME" "$TAG_TARGET"
fi

if [[ $TAG_NIXPKGS -eq 1 ]]
then
    if [[ ! -z "$NIXPKGS" ]]
    then
        stderr "This option is deprecated."
        stderr "Therefor it might be removed in the next version."
        stderr "Please complain in the official nixos-scripts repository."

        stdout "Trying to generate tag in $NIXPKGS"
        [[ ! -d "$NIXPKGS" ]] && \
            stderr "'$NIXPKGS' is not a directory, so can't be a nixpkgs clone" && \
            exit 1

        commit=$(nixos-version | sed -r 's,(.*)\.(.*)\ (.*),\2,')

        if [[ $DO_UPSTREAM_UPDATE -eq 1 ]]
        then
            dbg "Starting remote updating..."
            for remote in $UPSTREAM_REMOTE
            do
                dbg "Updating remote '$remote'"
                __git "$NIXPKGS" fetch "$remote"
                dbg "Ready updating remote '$remote'"
            done
            dbg "... ready remote updating"
        else
            dbg "Not updating remote upstream here."
        fi

        continue_question "Trying to create tag '$TAG_NAME' at '$NIXPKGS' on commit '$commit'" && \
            (__git "$NIXPKGS" tag $TAG_FLAGS_NIXPKGS "$TAG_NAME" $commit || \
            stderr "Could not create tag in nixpkgs clone")
    else
        stderr "Do not generate a tag in the nixpkgs clone"
        stderr "no NIXPKGS given."
        usage
        stderr "Continuing..."
    fi
else
    stdout "nixpkgs tag generating disabled"
fi

stdout "Ready."
