#!/bin/bash
Add-Type -assembly "system.io.compression.filesystem"
function getContentOfFile {
    param (
        $File
    )

    $stream = $File.Open()

    $reader = New-Object IO.StreamReader($stream)
    $text = $reader.ReadToEnd()
    $reader.Close()
    $stream.Close()

    
    return $text
}
function setContentOfFile {
    param (
        $File,
        [string] $Content
    )

    $stream = $File.Open()

    $writer = New-Object IO.StreamWriter($stream)
    $writer.Write($Content)
    $writer.Close()
    $stream.Close()
}

function base64sha512 {
    param( [string] $Path )
    $hasher = [System.Security.Cryptography.SHA512]::Create()
    if ($psVersionTable.psEdition -eq 'Desktop') {
        $content = Get-Content -Encoding byte $Path
    } else {
        $content = [System.IO.File]::GetAllBytes($Path) #Get-Content  -AsByteStream -Raw $Path
    }
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
function patchPath {
    param(
        [string] $Package
    )
    $PackageWithoutExt=[System.IO.Path]::GetFileNameWithoutExtension($Package)
    $Ext=".nupkg"
    if ($PackageWithoutExt.EndsWith(".symbols")) {
        $PackageWithoutExt=[System.IO.Path]::GetFileNameWithoutExtension($PackageWithoutExt)
        $Ext=".symbols$Ext"
    }
    $PACKAGES_DIR=Join-Path -Path (Split-Path -Path $Package) -ChildPath "$PackageWithoutExt-packageref$Ext"
    
    return $PACKAGES_DIR
}
function patchVersion {
    param(
        [ref] $Package,
        [string] $PackageName,
        [ref] $PackageVersion)
    $PackageVersionValue=$PackageVersion.Value
    $zip = [io.compression.zipfile]::OpenRead($Package.Value)
    $file = $zip.Entries | where-object { $_.Name -eq "$PackageName.nuspec"}
    $VERSION_FILE=getContentOfFile -File $file
    
    $PATCHED_PACKAGE_PATH=patchPath -Package $Package
    $zip.Dispose()
    if ($VERSION_FILE.Contains("-packageref</version>")){
        $Package.Value=$PATCHED_PACKAGE_PATH
        $PackageVersion.Value="$PackageVersionValue-packageref"
        return
    }

    $null = Copy-Item $Package.Value -Destination $PATCHED_PACKAGE_PATH -ErrorAction SilentlyContinue    
    $zip = [io.compression.zipfile]::Open($PATCHED_PACKAGE_PATH, "Update")
    $file = $zip.Entries | where-object { $_.Name -eq "$PackageName.nuspec"}
    $VERSION_FILE=$VERSION_FILE.Replace("</version>", "-packageref</version>")
    setContentOfFile -File $file -Content $VERSION_FILE
    
    
    $Package.Value=$PATCHED_PACKAGE_PATH
    $PackageVersion.Value="$PackageVersionValue-packageref"
    $zip.Dispose()
}

function ValueOrDefault {
    param($Value, $Default)
    if ($Value) {
        return $Value
    }
    return $Default
}

function installPackage {
    param(
        [string] $Package,
        [bool] $IsNew
    )
    $PACKAGE="$Package"
    $PACKAGE_FULLNAME=[System.IO.Path]::GetFileNameWithoutExtension($PACKAGE) #.TrimEnd(".symbols")

    $PACKAGE_VERSION=("$PACKAGE_FULLNAME" | Select-String -Pattern "[0-9](.[0-9])*(\-.*)*").Matches[0].Captures.Value
    $PACKAGE_NAME=$PACKAGE_FULLNAME.TrimEnd($PACKAGE_VERSION)
    $PATCHED_PATH=patchPath -Package $PACKAGE
    if($IsNew -Or !(Test-Path -Path $PATCHED_PATH)) {
        patchVersion -Package ([ref]$PACKAGE) -PackageName $PACKAGE_NAME -PackageVersion ([ref]$PACKAGE_VERSION)
    } else {
        $PACKAGE=$PATCHED_PATH
        $PACKAGE_VERSION="$PACKAGE_VERSION-packageref"
    }
    
    $PACKAGE_HASH=base64sha512 -Path "$PACKAGE"
    #NEW_PACKAGE_PATH="$(dirname "$PACKAGE")/$PACKAGE_NAME.$PACKAGE_VERSION-localPackage"
    #mv "$PACKAGE" "$NEW_PACKAGE_PATH"

    $GLOBAL_PACKAGE_DIR=(dotnet nuget locals all -l | Select-String -Pattern '^global-packages: (.*?)$').Matches[0].Groups[1]

    $PACKAGES_DIR=Join-Path -Path $GLOBAL_PACKAGE_DIR -ChildPath $PACKAGE_NAME.ToLower()
    if (Test-Path -Path "$PACKAGES_DIR" -PathType "Container") {
        $PACKAGE_VERSION_DIR=Join-Path -Path "$PACKAGES_DIR" -ChildPath "$PACKAGE_VERSION"
        if (Test-Path -Path "$PACKAGE_VERSION_DIR" -PathType Container) {
            $INSTALLED_PACKAGE_HASH_FILE=Join-Path -Path "$PACKAGE_VERSION_DIR" -ChildPath "$PACKAGE_NAME.$PACKAGE_VERSION.nupkg.sha512"
            
            $INSTALLED_PACKAGE_HASH=ValueOrDefault (Get-Content -Raw -Path "$INSTALLED_PACKAGE_HASH_FILE" -ErrorAction SilentlyContinue) ("")
            
            if ("$INSTALLED_PACKAGE_HASH" -ne "$PACKAGE_HASH") {
                $null = Remove-Item -LiteralPath "$PACKAGE_VERSION_DIR" -Force -Recurse -ErrorAction SilentlyContinue
            }
        }
    }
    echoResult -Package $PACKAGE -PackageVersion $PACKAGE_VERSION
}
#rm -rf /tmp/LocalPackageReferences || true
$null = New-Item -Path ([System.IO.Path]::GetTempPath()) -Name "LocalPackageReferences" -ItemType "directory" -ErrorAction SilentlyContinue
$LocalPackageRefPath = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "LocalPackageReferences"
$IS_OUTPUT_FILE=""
$Env:DOTNET_CLI_UI_LANGUAGE = "en"
#(chcp 437 | Out-Null)
#$OLD_LOCALE=Get-WinSystemLocale
$MSBUILD_OUT=dotnet pack $args[0] -o $LocalPackageRefPath -v detailed --configuration Debug /p:DebugType=embedded
#Set-WinSystemLocale $OLD_LOCALE

$PARSE_MODE=0

function TryInstall {
    param([string] $PackageName, [bool] $IsNew)
    if ($PackageName.EndsWith(".nupkg") -And (Test-Path -Path $PackageName)) {
        installPackage -Package $PackageName -IsNew $IsNew
    }
}

foreach($line in $MSBUILD_OUT) {
    #Add-Content -Path ".\tmp.txt" -Value $line
    switch($PARSE_MODE) {
        0 {
            if ($line -Match "[0-9]+:[0-9]+>.*?(`"|')GenerateNuspec(`"|').*?(`"|').*?NuGet.Build.Tasks.Pack.targets(`"|')") {
                $PARSE_MODE=1
            }
        }
        1 {
            if ($line -Match "^       .*?: ") {
                $PARSE_MODE=2
            } elseif($line.Contains("PackTask") -And $line.Contains("NuGet.Build.Tasks.Pack.dll") -And $line -Match "^       ") {
                $PARSE_MODE=4
            }
        }
        2 {
            if ($line -Match "^       .*?: ") {
                $PARSE_MODE=3
            }
        }
        3 {
            if ($line.StartsWith("        ")) {
                TryInstall -PackageName $line.TrimStart() -IsNew $false
            } else {
                $PARSE_MODE=0
            }
        }
        4 {
            $PARSE_MODE=5
        }
        5 {
            if ($line.StartsWith("        ")) {
                $PACKAGE_SUCCESS = $line | Select-String -Pattern ".*? (`"|')(?<SuccessPackage>.*\.nupkg)(`"|').*?`."
                if ($PACKAGE_SUCCESS) {
                    TryInstall -PackageName $PACKAGE_SUCCESS.Matches.Groups[3].Value -IsNew $true
                }
            } else {
                $PARSE_MODE=0
            }
        }
    }
    
}

