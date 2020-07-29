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


if [ -n "$CLEAN" ]; then
    cd $BASE/src/app/c
    rm -rf build sdkconfig sdkconfig.old
    cd $BASE/src/test
    rm -rf build sdkconfig sdkconfig.old
    cd $BASE/src/hwtest/app
    rm -rf build build_testpart sdkconfig sdkconfig.old
    cd $BASE
fi

if [ -n "$RUN_CEEDLING" ]; then
    export CEEDLING_MAIN_PROJECT_FILE=ceedling.yml
    run_ceedling() {
        path=$1; shift
        status=0
        cd $path
        if [ -f ceedling.yml ]; then
            # run ceedling tests here
            ceedling clean
            ceedling test:all
            ceedling gcov:all utils:gcov
            status=$?
        fi
        return $status
    }
    clean_ceedling() {
        path=$1; shift
        status=0
        cd $path
        if [ -f ceedling.yml ]; then
            # run ceedling tests here
            ceedling clean
            # clean up
            rm -rf build
        fi
        return $status
    }

    # loop through src/app/c/main and src/app/c/components/* directories
    for d in $BASE/src/app/c/main/ $BASE/src/app/c/components/*/; do
        run_ceedling $d
        ret=$?
        if [ "0" -ne "$ret" ]; then
            exit $ret
        fi
    done

    cd $BASE
    lcov -c --directory . --output-file cove.info
    lcov -r cove.info -o cove1.info '*/third-party/*'
    genhtml cove1.info -o code-cov
    # loop through src/app/c/main and src/app/c/components/* directories and clean
    for d in $BASE/src/app/c/main/ $BASE/src/app/c/components/*/; do
        clean_ceedling $d
        ret=$?
        if [ "0" -ne "$ret" ]; then
            exit $ret
        fi
    done
    cd $BASE
    tar -czf code-cov-report.tar.gz code-cov
    rm -f cove.info
    rm -f cove1.info
    cp code-cov-report.tar.gz /opt/output/.
    cd $BASE
fi

if [ -n "$BUILD" ]; then
    # Build hwtest firmware for test app partition
    cd $BASE/src/hwtest/app
    SDKCONFIG_DEFAULTS=$PWD/sdkconfig.testpart.defaults idf.py --build-dir $PWD/build_testpart build
    TEST_PARTITION_APP=$PWD/build_testpart/firespy_hwtest.bin
    # Clean up the sdkconfig files so the next build will start from a clean slate
    rm -f sdkconfig sdkconfig.old

    # Build selected app firmware
    cd $APP_DIR

    # Customise configuration manually
    # Check and modify SSID and password if they are set in the env
    if [ -n "$ESP32_SSID" ]; then
        updateconf="${updateconf}\"WIFI_SSID\":\"$ESP32_SSID\","
    fi
    if [ -n "$ESP32_PASSWORD" ]; then
        updateconf="${updateconf}\"WIFI_PASSWORD\":\"$ESP32_PASSWORD\","
    fi
    # Apply configuration if it has been modified
    if [ -n "$updateconf" ]; then
        # Configuration needs to be updated, so start the confserver and send
        # the JSON data to STDIN
        updatejson="{\"version\":2,\"save\":null,\"set\":{${updateconf%?}}}"
        echo "JSON config to update $updatejson"
        echo $updatejson | idf.py confserver >confserver.txt
    fi

    TEST_PARTITION_APP="$TEST_PARTITION_APP" idf.py build
    cd $BASE
fi

if [ -n "$RUN_TESTS" ]; then
    if [ ! -n "$PORT" ]; then
        # Port must be set if we're going to run the tests
        echo "Error: -p argument is required with -t"
        exit -1
    fi
    cd $BASE/src/test
    idf.py -p $PORT flash && $BASE/scripts/unity_output_parse.py --port $PORT
    cd $BASE
fi

# The deploy component of this script deploys the build firmware images to a common
# directory and adds them to a gzipped tarball. On a working system, the contents
# of the gzipped tarball can then be installed onto an empty ESP32 module.
if [ -n "$DEPLOY" ]; then
    cd $APP_DIR
    file_list="build/bootloader/bootloader.bin build/ota_data_initial.bin"
    file_list="$file_list build/partition_table/partition-table.bin"
    case $APP_DIR in
        */app/c) file_list="$file_list build/firespy.bin build/firespy.elf build/hwtest.bin" ;;
        */hwtest/app) file_list="$file_list build/firespy_hwtest.bin build/firespy_hwtest.elf" ;;
        */test) file_list="$file_list build/firespy_test.bin build/firespy_test.elf" ;;
    esac
    # If this was locally built, and the dev_keys.bin or nvs.bin file(s) exist, copy that to the
    # release tarball as well. (NB: for normal builds these will not be present).
    dev_keys_bin="build/dev_keys.bin"
    if [ -f $dev_keys_bin ]; then
        file_list="$file_list $dev_keys_bin"
    fi
    nvs_bin="build/nvs.bin"
    if [ -f $nvs_bin ]; then
        file_list="$file_list $nvs_bin"
    fi
    for v in $file_list; do
        cp $v $DEPLOY/.
    done
    $RELEASE_SCRIPT_DIR/bundle.sh $DEPLOY
    cp $RELEASE_SCRIPT_DIR/build/*.tar.gz $DEPLOY/.
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

