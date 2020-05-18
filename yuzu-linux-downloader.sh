#!/bin/bash

CHANNEL=""

CHANNELS="earlyaccess" #"earlyaccess|canary|mainline" can't find the others

usage(){
echo -e "Usage: $0 [-c CHANNEL ] [-d DIRECTORY] LOGIN_TOKEN\\n\\nGet your login token from https://profile.yuzu-emu.org/\\n\\nCHANNEL(s):$CHANNELS\\n\\nDIRECTORY: Where the yuzu program will be downloaded and compiled. Defaults to pwd \\n\\nOnce installed yuzu can be run via \$DIRECTORY/\$BUILDNAME/build/bin/yuzu\\n\\nBefore running the script you have to give it permission to execute\\nchmod +x ./yuzu-early-access.sh"
}

exit_abnormal(){
    usage
    exit 1
}

#Check for args
if [[ ! $@ =~ ^\-.+ ]]
then
    exit_abnormal
fi

while getopts ":c:d:h" options; do
    case "${options}" in
        h) usage; exit 0;;        
        c) CHANNEL=${OPTARG};;
        d) DIRECTORY=${OPTARG};
           [[ -d $DIRECTORY ]] || mkdir $DIRECTORY;
           cd $DIRECTORY;;
        \? )
           exit_abnormal;;
        :)
            echo "Error: -${OPTARG} requires an argument or invalid option."
            exit_abnormal
    esac
done

shift $((OPTIND - 1)) # sets the final argument to $1
PROFILE=$1
if [ "$PROFILE" == "" ] ;then
    echo "Error: Missing LOGIN_TOKEN"
    exit_abnormal
fi
    
NAME_TOKEN=$(echo "$PROFILE=" | base64 -d)
NAME=$(echo $NAME_TOKEN | awk -F ":" '{print $1}')
TOKEN=$(echo $NAME_TOKEN | awk -F ":" '{print $2}')
if [ "$CHANNEL" == "" ] ;then    
    CHANNEL="earlyaccess"
fi

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


echo "Unziping Yuzu source."
[[ -d $FILE ]] && rm -rf $FILE # make sure previous files are removed
tar -xf $TAR_FILE
    
if [ -f $FILE ]; then
    echo "Error: Failed to unizp $TAR_FILE."
    exit_abnormal
fi

echo "Preparing to install (this may take a moment)." 
cd $FILE
find -type f -print0|xargs -0 -P $(nproc) -I % sed -i 's/\r$//' %

echo "Patching windows build to work with linux."
wget http://ix.io/2mBY && patch -p1 < 2mBY
mkdir build && cd build
cmake .. -GNinja
ninja
