#!/usr/bin/env bash

TESTNAME=$1
ED2EXE=${2:-ed_2.2-dbg}

if [ -z "$TESTNAME" ]; then
    echo "Please specify a test to run."
    exit 1
fi

ED2IN="Templates/ED2IN-$TESTNAME"

if [ ! -f "$ED2IN" ]; then
    echo "Test file $ED2IN does not exist"
    exit 1
fi

DATA_COMMON="common"
if [ ! -d "$DATA_COMMON" ]; then
    echo "Downloading common data"
    wget "https://github.com/ashiklom/edts-datasets/releases/download/common/common.tar.gz"
    tar -xf "$DATA_COMMON.tar.gz"
else
    echo "Common data $DATA_COMMON already exists"
fi

# Test files take the form "SITENAME[.options]".
# For example, `umbs.bg` for bare-ground run at UMBS.
# They can also just be the site name -- e.g. `harvard-forest`.
#
# `SITENAME` must match the tags and file names found at
# https://github.com/ashiklom/edts-datasets/releases.

SITE=${TESTNAME%.*}
if [ ! -d "$SITE" ]; then
    echo "Downloading data for site $SITE"
    wget "https://github.com/ashiklom/edts-datasets/releases/download/$SITE/$SITE.tar.gz"
    tar -xf "$SITE.tar.gz"
else
    echo "Data for site $SITE already exists"
fi

OUTDIR="test-outputs/$TESTNAME"
echo "Running ED2. Outputs will be saved to $OUTDIR"
mkdir -p "$OUTDIR"

mkdir -p "test-logs"
LOGFILE="test-logs/$TESTNAME"

# Is this MacOS? If so:
# (1) Don't change the stack size
# (2) Use `lldb` instead of `gdb` for debugging
if uname -a | grep -q -i "darwin"; then
    ISMACOS=yes
fi

if [ -z $ISMACOS ]; then
    # Remove the stack limit. Otherwise, ED2 will mysteriously segfault early in
    # its excution. But don't do this check on MacOS.
    ulimit -s unlimited
fi

# Run without OMP.
# TODO: Test execution with OMP
# Try to run through a debugger for better error information.
# First, try `gdb`, then `lldb`, and finally fall back
if [ -z $ISMACOS ] && command -v gdb > /dev/null; then
    OMP_NUM_THREADS=1 gdb "$ED2EXE" -ex "run -s -f $ED2IN" | tee "$LOGFILE"
elif [ $ISMACOS ] && command -v lldb > /dev/null; then
    OMP_NUM_THREADS=1 lldb --batch -o run -- "$ED2EXE" -s -f "$ED2IN" | tee "$LOGFILE"
else
    OMP_NUM_THREADS=1 "$ED2EXE" -s -f "$ED2IN" | tee "$LOGFILE"
fi

if grep -q "Time integration ends" "$LOGFILE"; then
    echo "Run successful!"
    exit 0
else
    echo "Run failed. For details, see $LOGFILE"
    exit 1
fi
