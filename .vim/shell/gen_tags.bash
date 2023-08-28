#!/bin/bash

set -e

# Various directories(?) excluded by gtags/uctags by default. Note that
# universal ctags has a bug where directory exclusions don't work when using the
# -L option
find_excludes=(
    .DS_Store           # macOS attributes
    .arch-ids           # GNU arch
    .arch-inventory     # GNU arch
    .bzr                # GNU Bazaar
    .dvi                # Latex?
    .git
    .hg                 # Mercurial
    .svn
    BitKeeper
    CVS
    CVSROOT
    EIFGEN              # ???
    PENDING             # ???
    RCS                 # ???
    RESYNC              # ???
    SCCS
    _darcs
    autom4te.cache      # autoconf
    {arch}              # GNU arch
)

have_command() {
    [ -x "$(command -v "$1")" ]
}

check_find_files0_from() {
    # Check find has the -files0-from option
    find -files0-from /dev/null &>/dev/null
}

if [ -n "$1" ]
then
    # Generate tags in the directory given
    cd -- "$1"
else
    start_dir="$PWD"

    until [ -d .svn ] || [ -d .git ] || [ "$PWD" = / ]
    do
        cd ..
    done

    if [ ! -d .git ] && [ ! -d .svn ]
    then
        echo 'Cannot automatically determine project root'
        exit 1
    fi
fi

# If a version control directory is found, only process the files under version
# control. The commands below will also list files that have been added but not
# committed.
if [ -d .git ] && have_command git
then
    echo 'Generating gtags.files via git ls-files'
    git ls-files >gtags.files
elif [ -d .svn ] && have_command svn && check_find_files0_from
then
    # Note svn ls needs a connection to the server and can be very slow. It will
    # also miss files that have been added but not committed.
    echo 'Generating gtags.files via svn status'
    svn status --no-ignore --verbose |
        sed -e '/^[!?I]/ d' \
            -e 's:^.\{28\}[^ ]* *::' \
            -e 's:\\:/:g' |
        tr -d \\r |
        tr \\n \\0 |
        find -files0-from - -maxdepth 0 -type f \
        >gtags.files
else
    echo 'Generating gtags.files via find'

    exclude_args=(-name "${find_excludes[0]}")
    for exclude in "${find_excludes[@]:1}"
    do
        exclude_args+=(-o -name "$exclude")
    done

    find \( "${exclude_args[@]}" \) -prune -o -type f >gtags.files
fi

# TODO, global -u
echo 'Starting gtags'
TIMEFORMAT='Completed gtags generation in %1Rs'
time gtags \
        --accept-dotfiles \
        --gtagslabel=native-pygments \
        --gtagsconf=/usr/share/gtags/gtags.conf \
        &

echo 'Starting universal ctags'
TIMEFORMAT='Completed ctags generation in %1Rs'

# Add the "Unknown" language to generate file tags for every file
# TODO, assuming this is universal ctags...
time ctags \
        --languages=+Unknown \
        --map-C=+.h --kinds-C='+{prototype}{externvar}' \
        --fields='-{typeref}{epoch}' \
        --extras='+{inputFile}' \
        --exclude=@tags_exclusions \
        -L gtags.files \
        &

wait -n
wait -n
