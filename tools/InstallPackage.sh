#!/bin/bash
trim() {
    local var="$*"
    # remove leading whitespace characters
    var="${var%\ *}"
    # remove trailing whitespace characters
    var="${var#*\ }"
   
    printf '%s' "$var"
}
echoResult() {
    #echo $PACKAGE_NAME
    echo "$PACKAGE;$PACKAGE_VERSION"
}

patchedPath () {
    PATCHED_PACKAGE_PATH=${1/\.nupkg/-packageref\.nupkg}
    PATCHED_PACKAGE_PATH=${PATCHED_PACKAGE_PATH/\.symbols\.-packageref\.nupkg/-packageref\.symbols\.nupkg}
    PATCHED_PACKAGE_PATH="$(dirname "$PATCHED_PACKAGE_PATH")/$(basename "$PATCHED_PACKAGE_PATH")"
}

patchVersion() {
    VERSION_FILE=$(unzip -p "$1" "$2.nuspec")
    
    patchedPath "$1"
    if [[ $VERSION_FILE == *"-packageref</version>"* ]]; then
        PACKAGE="$PATCHED_PACKAGE_PATH"
        PACKAGE_VERSION="$PACKAGE_VERSION-packageref"
        return
    fi
    cp "$PACKAGE" "$PATCHED_PACKAGE_PATH" &> /dev/null
    PACKAGE="$PATCHED_PACKAGE_PATH"
    zip -d "$PACKAGE" "$2.nuspec" &> /dev/null
    VERSION_FILE=${VERSION_FILE/\<\/version\>/-packageref\<\/version\>}
    TEMP_VERSION_FILE=$(mktemp)
    echo "$VERSION_FILE">"/tmp/LocalPackageReferences/$2.nuspec"
    pushd "/tmp/LocalPackageReferences" &> /dev/null
    zip -u "$PACKAGE" "$2.nuspec" &> /dev/null
    rm "$2.nuspec" &> /dev/null
    popd &> /dev/null
    PACKAGE_VERSION="$PACKAGE_VERSION-packageref"
}

installPackage() {
    PACKAGE="$1"
    PACKAGE_FULLNAME=$(basename "$PACKAGE")
    PACKAGE_FULLNAME="${PACKAGE_FULLNAME%.nupkg}"
    PACKAGE_VERSION=$(echo "$PACKAGE_FULLNAME" | grep -oP '[0-9](.[0-9])*(\-.*)*')
    PACKAGE_NAME=${PACKAGE_FULLNAME%\.${PACKAGE_VERSION}}
    PACKAGE_HASH=$(openssl dgst -binary -sha512 "$PACKAGE" | openssl base64 -A)
    #NEW_PACKAGE_PATH="$(dirname "$PACKAGE")/$PACKAGE_NAME.$PACKAGE_VERSION-localPackage"
    #mv "$PACKAGE" "$NEW_PACKAGE_PATH"

    GLOBAL_PACKAGE_DIR=$(dotnet nuget locals all -l | grep '^global-packages: ')

    GLOBAL_PACKAGE_DIR=${GLOBAL_PACKAGE_DIR#*: }

    PACKAGES_DIR=$(find "$GLOBAL_PACKAGE_DIR" -maxdepth 1 -iname "$PACKAGE_NAME" 2> /dev/null || true)

    if [ -d "$PACKAGES_DIR" ]; then
        PACKAGE_VERSION_DIR_PACKAGEREF=$(find "$PACKAGES_DIR" -maxdepth 1 -iname "$PACKAGE_VERSION-packageref")
        if [ -d "$PACKAGE_VERSION_DIR_PACKAGEREF" ]; then
            INSTALLED_PACKAGE_HASH_FILE=$(find "$PACKAGE_VERSION_DIR_PACKAGEREF" -maxdepth 1 -iname "$PACKAGE_NAME.$PACKAGE_VERSION-packageref.nupkg.sha512")
            
            INSTALLED_PACKAGE_HASH=$(cat "$INSTALLED_PACKAGE_HASH_FILE" 2> /dev/null || echo "")
            
            if [ "$INSTALLED_PACKAGE_HASH" != "$PACKAGE_HASH" ]; then
                rm -rf "$PACKAGE_VERSION_DIR_PACKAGEREF"
            else
                patchedPath
                PACKAGE="$PATCHED_PACKAGE_PATH"
                PACKAGE_VERSION="$PACKAGE_VERSION-packageref"
                echoResult
                return
            fi
        fi
        PACKAGE_VERSION_DIR=$(find "$PACKAGES_DIR" -maxdepth 1 -iname "$PACKAGE_VERSION")
        if [ -d "$PACKAGE_VERSION_DIR" ]; then
            INSTALLED_PACKAGE_HASH_FILE=$(find "$PACKAGE_VERSION_DIR" -maxdepth 1 -iname "$PACKAGE_NAME.$PACKAGE_VERSION.nupkg.sha512")
            
            INSTALLED_PACKAGE_HASH=$(cat "$INSTALLED_PACKAGE_HASH_FILE" 2> /dev/null || echo "")
            
            if [ "$INSTALLED_PACKAGE_HASH" != "$PACKAGE_HASH" ]; then
                rm -rf "$PACKAGE_VERSION_DIR"
            else
                echoResult
                return
            fi
        fi
    fi
    patchVersion "$PACKAGE" "$PACKAGE_NAME" "$PACKAGE_VERSION"
    echoResult
}

#rm -rf /tmp/LocalPackageReferences || true
mkdir /tmp/LocalPackageReferences 2> /dev/null || true

TEMP_BUILD_FILE=$(mktemp)
LC_ALL=en dotnet pack "$1" -o /tmp/LocalPackageReferences -v detailed --configuration Debug /p:DebugType=embedded > "$TEMP_BUILD_FILE"
# echo $TEMP_BUILD_FILE
PACKAGE_SUCCESS=$(grep -oP "(?<=Successfully created package ').*(?='.)" "$TEMP_BUILD_FILE")
if [ -f "$PACKAGE_SUCCESS" ]; then
    installPackage $PACKAGE_SUCCESS
else
    IS_OUTPUT_FILE=false
    while IFS= read -r line
    do
        PACKAGE_CREATED=$(trim $(echo "$line"))
        if [ -f "$PACKAGE_CREATED" ]; then
            installPackage $PACKAGE_CREATED
        fi
    done < <(awk '/^(       )Output files: $/{flag=1;next}!/^(       ).*/{flag=0;next}flag{if ($1 ~ /\.nupkg/){ print $1; }}' "$TEMP_BUILD_FILE")


fi