#!/bin/sh -e

BASE=`dirname $0`
case $BASE in "/"*) ;; *)
    BASE=$PWD/$BASE
esac
APP_DIR=${APP_DIR:-$BASE/src/app/c}

usage()
{
cat << EOF
usage: $0 options

This script builds the FireSpy firmware.

OPTIONS:
   -?|-h            Show this message
   -c               Clean all firmware
   -b               Build firmware
                    NB: Set ESP32_SSID and ESP32_PASSWORD env variables to customise
                    the AP that the device connects to.
   -p               Serial port for device connection. Set this if different from
                    /dev/ttyUSB0
   -d               Deploy firmware to firmware bundle
   -g               Ceedling tests: Clean, test all and remove build directory
   -r               Run firmware on board
   -t               Run all tests on hardware

EOF
}

while getopts "h?bcd:gp:rt" opt; do
    case "$opt" in
    h|\?)
        usage
        exit 0
        ;;
    b)
        BUILD=1
        ;;
    c)
        CLEAN=1
        ;;
    d)
        DEPLOY=$OPTARG
        if [ ! -d $DEPLOY ]; then
            echo "Error: DEPLOY env variable must be a valid directory"
            exit -1
        elif [ "$(ls $DEPLOY | wc -l)" -ne "0" ]; then
            # Erase directory contents
            rm -rf $DEPLOY/*
        fi
        ;;
    g)
        RUN_CEEDLING=1
        ;;
    p)
        PORT=$OPTARG
        ;;
    r)
        RUN_FW=1
        ;;
    t)
        CLEAN=1
        BUILD=1
        RUN_TESTS=1
        ;;
    esac
done


if [ -n "$RUN_CEEDLING" ]; then
    cd $BASE
    tar -czf code-cov-report.tar.gz code-cov
    rm -f cove.info
    rm -f cove1.info
    cp code-cov-report.tar.gz /opt/output/.
    cd $BASE
fi


if [ -n "$RUN_FW" ]; then
    if [ -n "$PORT" ]; then
        cd $APP_DIR
        idf.py -p $PORT flash monitor
        cd $BASE
    else
        echo "Option -p is required with -r"
        usage
        exit -1
    fi
fi

