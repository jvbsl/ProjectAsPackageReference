#!/bin/bash

function base64sha512 {
    param( [string] $Path )
    $hasher = [System.Security.Cryptography.SHA512]::Create()
    $content = Get-Content -Encoding byte $Path
    $hash = [System.Convert]::ToBase64String($hasher.ComputeHash($content))
    return $hash
}

function echoResult {
    param(
        [string] $Package,
        [string] $PackageVersion
    )
    #Write-Host $PACKAGE_NAME
    Write-Host "$Package;$PackageVersion"
}

function installPackage {
    param(
        [string] $Package
    )
    $PACKAGE="$Package"
    $PACKAGE_FULLNAME=[System.IO.Path]::GetFileNameWithoutExtension($PACKAGE)

    $PACKAGE_VERSION=("$PACKAGE_FULLNAME" | Select-String -Pattern "[0-9](.[0-9])*(\-.*)*").Matches[0].Captures.Value
    $PACKAGE_NAME=$PACKAGE_FULLNAME.TrimEnd($PACKAGE_VERSION)
    $PACKAGE_HASH=base64sha512 -Path "$PACKAGE"
    #NEW_PACKAGE_PATH="$(dirname "$PACKAGE")/$PACKAGE_NAME.$PACKAGE_VERSION-localPackage"
    #mv "$PACKAGE" "$NEW_PACKAGE_PATH"

    $GLOBAL_PACKAGE_DIR=(dotnet nuget locals all -l | Select-String -Pattern '^global-packages: (.*?)').Matches[0].Groups[1]

    $PACKAGES_DIR=Join-Path -Path "$GLOBAL_PACKAGE_DIR" -ChildPath "$PACKAGE_NAME"

    if (Test-Path -Path "$PACKAGES_DIR" -PathType "Container") {
        $PACKAGE_VERSION_DIR=Join-Path -Path "$PACKAGES_DIR" -ChildPath "$PACKAGE_VERSION"
        if (Test-Path -Path "$PACKAGE_VERSION_DIR" -PathType Container) {
            $INSTALLED_PACKAGE_HASH_FILE=Join-Path -Path "$PACKAGE_VERSION_DIR" -ChildPath "$PACKAGE_NAME.$PACKAGE_VERSION.nupkg.sha512"
            
            $INSTALLED_PACKAGE_HASH=Get-Content -Raw -Path "$INSTALLED_PACKAGE_HASH_FILE" -ErrorAction SilentlyContinue || ""
            
            if ("$INSTALLED_PACKAGE_HASH" -ne "$PACKAGE_HASH") {
                Remove-Item -LiteralPath "$PACKAGE_VERSION_DIR" -Force -Recurse -ErrorAction SilentlyContinue
            }
        }
    }
    #echoResult -Package "$PACKAGE" -PackageVersion "$PACKAGE_VERSION"
}
#rm -rf /tmp/LocalPackageReferences || true
New-Item -Path ([System.IO.Path]::GetTempPath()) -Name "LocalPackageReferences" -ItemType "directory" -ErrorAction SilentlyContinue

$IS_OUTPUT_FILE=$false
foreach($line in (dotnet pack --include-symbols "$1" -o /tmp/LocalPackageReferences -v detailed --configuration Debug)) {
    if ($IS_OUTPUT_FILE) {
        $line=$line.TrimEnd()
        if ($line.EndsWith(".symbols.nupkg") -And (Test-Path -Path $line)) {
            installPackage -Package $line
        }
    }
    elseif ($line.StartsWith("       Output files: ")) {
        $IS_OUTPUT_FILE=$true
    } else {
        $PACKAGE_SUCCESS=($line | Select-String -Pattern "  (Successfully created package '(?<SuccessPackage>.*\.symbols\.nupkg)'\.)")
        if ($PACKAGE_SUCCESS) {
            $PACKAGE_SUCCESS=$PACKAGE_SUCCESS.Matches.Groups.Captures[2]
            if (Test-Path -Path $PACKAGE_SUCCESS) {
                installPackage -Package $PACKAGE_SUCCESS
            }
        }
    }
    
}

