#!/bin/bash

CHANNEL=""

CHANNELS="earlyaccess|mainline"

usage(){
echo -e "Usage: $0 [-c CHANNEL ] [-d DIRECTORY] [LOGIN_TOKEN]\\n\\nFor building Early Access, get your login token from https://profile.yuzu-emu.org/\\n\\nCHANNEL(s):$CHANNELS\\n\\nDIRECTORY: Where the yuzu program will be downloaded and compiled. Defaults to pwd\\n\\nBefore running the script you have to give it permission to execute\\nchmod +x ./yuzu-early-access.sh"
}

exit_abnormal(){
    usage
    exit 1
}

export PATH="/usr/lib/ccache/bin/:$HOME/.local/bin/:$PATH"

# Check installed software
declare -a reqsw=("curl" "wget" "conan" "g++" "cmake" "python2" "tar" "patch")
for i in "${reqsw[@]}"
do
    if ! [ -x "$(command -v $i)" ]; then
        echo "You must install $i"
        exit 1
    fi
done

if [ -x qmake ]; then
    echo "You must install QT (possibly dev package)"
    exit 1
fi

while getopts ":c:d:i:hgolf" options; do
    case "${options}" in
        h) usage; exit 0;;        
        c) CHANNEL=${OPTARG};;
        d) DIRECTORY=${OPTARG};
           [[ -d $DIRECTORY ]] || mkdir $DIRECTORY;
           cd $DIRECTORY;;
        i) instdir=$OPTARG;;
        g) debug=1;;
        o) opts=1;;
        l) clangbuild=1;;
        w) webengine=1;;
        :)
            echo "Error: -${OPTARG} requires an argument or invalid option."
            exit_abnormal
    esac
done

if [ "$CHANNEL" == "" ]; then
    echo -e "Please select your Channel\nNote: to avoid this in the future, specify your channel with -c"
    echo -e "1. mainline\n2. earlyaccess"
    read chan

    if [ "$chan" == "earlyaccess" ] || [ "$chan" == "mainline" ] || [ "$chan" == "1" ] || [ "$chan" == "2" ]; then
        case "$chan" in
        "earlyaccess" | "mainline")
            CHANNEL=$chan;;
        "1")
            CHANNEL="mainline";;
        "2")
            CHANNEL="earlyaccess";;
        esac
    else
        exit_abnormal
    fi
fi

if [ "$CHANNEL" == "earlyaccess" ]; then
    shift $((OPTIND - 1)) # sets the final argument to $1
    PROFILE=$1
    if [ "$PROFILE" == "" ] ;then
        echo "Please enter your EA login token:"
        read token
        if ! [ "$token" == "" ]; then
            PROFILE=$token
        else
            exit_abnormal
        fi
    fi

    NAME_TOKEN=$(echo "$PROFILE" | base64 -d)
    NAME=$(echo $NAME_TOKEN | awk -F ":" '{print $1}')
    TOKEN=$(echo $NAME_TOKEN | awk -F ":" '{print $2}')

    echo "Preparing to download channel:$CHANNEL"
    BEARER_TOKEN=$(curl -s -X POST -H "X-USERNAME: $NAME" -H "X-TOKEN: $TOKEN" https://api.yuzu-emu.org/jwt/installer/)
    URL=$(curl -s https://api.yuzu-emu.org/downloads/$CHANNEL | grep -A 0 "yuzu-windows-msvc-source" | tail -1 | awk -F ": " '{print $2}' | sed 's/\"//g')
    TAR_FILE=$(basename $URL)
    FILE=$(echo $TAR_FILE | sed 's/.tar.xz//g')


    echo "Downloading Yuzu source."
    curl -X GET -H "Authorization: Bearer $BEARER_TOKEN" $URL > $TAR_FILE
    if ! [ -f $TAR_FILE ]; then
        echo "Error: Failed to download $URL."
        exit_abnormal
    fi

elif [ "$CHANNEL" == "mainline" ]; then
    URL=$(curl --silent "https://api.github.com/repos/yuzu-emu/yuzu-mainline/releases/latest" \
    | grep "yuzu-windows-.*xz" | tail -1 | awk -F ": " '{print $2}' | sed 's/\"//g')
    TAR_FILE=$(basename $URL)
    FILE=$(echo $TAR_FILE | sed 's/.tar.xz//g')

    echo "Downloading Yuzu source."
    wget $URL
fi

echo "Unzipping Yuzu source."
[[ -d $FILE ]] && rm -rf $FILE # make sure previous files are removed
tar -xf $TAR_FILE
    
if [ -f $FILE ]; then
    echo "Error: Failed to unzip $TAR_FILE."
    exit_abnormal
fi

echo "Preparing to build and install (this may take a moment)." 
cd $FILE
find -type f -print0|xargs -0 -P $(nproc) -I % sed -i 's/\r$//' %

echo "Patching Windows source to work with linux."
wget https://github.com/RealJohnGalt/yuzu-linux-downloader/raw/master/linuxsupport.patch && patch -p1 < linuxsupport.patch
if [ "CHANNEL" == "earlyaccess" ]; then
    wget https://patch-diff.githubusercontent.com/raw/yuzu-emu/yuzu/pull/4280.diff && patch -p1 < 4280.diff
fi

if [[ "$opts" == "1" ]]; then
    if [[ "$clangbuild" == "1" ]]; then
        echo "Preparing for optimized clang build. If there are issues, ensure your llvm installation has polly and lld."
        export CFLAGS="-mllvm -polly -mllvm -polly-parallel -lgomp -mllvm -polly-vectorizer=stripmine -flto=thin -fno-plt -march=native -mtune=native -O3 -pipe -Wno-unused-command-line-argument"
        export CXXFLAGS="-mllvm -polly -mllvm -polly-parallel -lgomp -mllvm -polly-vectorizer=stripmine -flto=thin -fno-plt -march=native -mtune=native -O3 -pipe -Wno-unused-command-line-argument"
       export LDFLAGS="-fuse-ld=lld -Wl,--as-needed,-O1,--sort-common,-z,now,-z,relro"
    else
        echo "Preparing for optimized gcc build."
        export CFLAGS="-march=native -O3 -fuse-linker-plugin -flto"
        export CXXFLAGS="-march=native -O3 -fuse-linker-plugin -flto"
    fi
fi

if [[ "$clangbuild" == "1" ]]; then
    export CC="clang"
    export CXX="clang++"
    if [ "CHANNEL" == "mainline" ]; then
        wget https://github.com/RealJohnGalt/yuzu-linux-downloader/raw/master/clangreverts.patch && patch -p1 < clangreverts.patch
    fi
fi

mkdir build && cd build
if [[ "$debug" == "" ]]; then
    if [[ "$webengine" == 1 ]]; then
        cmake .. -DCMAKE_BUILD_TYPE=Release -DYUZU_USE_QT_WEB_ENGINE=ON
    else
        cmake .. -DCMAKE_BUILD_TYPE=Release
    fi
else
    cmake .. -DCMAKE_BUILD_TYPE=RelWithDebInfo
fi

make -j$(($(nproc) -1))

if [[ "$debug" == "" ]]; then
    strip bin/*
fi

bindir="$(pwd -L)/bin"

if [[ "$instdir" == "" ]]; then
    instdir=$HOME/.yuzubin
fi

mkdir -p $instdir
realinstdir=$(realpath $instdir)
cp -f ./bin/* $realinstdir

echo "Your build should be in $realinstdir"
echo "To add this to your PATH, you may run the following:"
echo "echo 'PATH=$realinstdir:\$PATH' >> ~/.profile && source ~/.profile"
