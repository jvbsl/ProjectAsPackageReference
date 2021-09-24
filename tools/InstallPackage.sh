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

    PACKAGES_DIR=$(find "$GLOBAL_PACKAGE_DIR" -maxdepth 1 -iname "$PACKAGE_NAME")

    if [ -d "$PACKAGES_DIR" ]; then
        PACKAGE_VERSION_DIR=$(find "$PACKAGES_DIR" -maxdepth 1 -iname "$PACKAGE_VERSION")
        if [ -d "$PACKAGE_VERSION_DIR" ]; then
            INSTALLED_PACKAGE_HASH_FILE=$(find "$PACKAGE_VERSION_DIR" -maxdepth 1 -iname "$PACKAGE_NAME.$PACKAGE_VERSION.nupkg.sha512")
            
            INSTALLED_PACKAGE_HASH=$(cat "$INSTALLED_PACKAGE_HASH_FILE" 2> /dev/null || echo "")
            
            if [ "$INSTALLED_PACKAGE_HASH" != "$PACKAGE_HASH" ]; then
                rm -rf "$PACKAGE_VERSION_DIR"
            fi
        fi
    fi
    echoResult
}
#rm -rf /tmp/LocalPackageReferences || true
mkdir /tmp/LocalPackageReferences 2> /dev/null || true

TEMP_BUILD_FILE=$(mktemp)
dotnet pack "$1" -o /tmp/LocalPackageReferences -v detailed --configuration Debug /p:PackageVersion=9.9.9-beta > "$TEMP_BUILD_FILE"
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
    done < <(grep -A100000 '^       Output files: $' "$TEMP_BUILD_FILE" | grep '.nupkg$')


fi

