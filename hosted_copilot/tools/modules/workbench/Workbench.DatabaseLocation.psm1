Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-WorkbenchDatabaseLocatorPath {
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$BranchRef,
        [string]$StorageDirectory = (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'hosted-workbench/database-locations')
    )
    $scope = [IO.Path]::GetFullPath($RepositoryRoot) + "`n" + $BranchRef
    $key = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($scope))).ToLowerInvariant()
    Join-Path $StorageDirectory ($key + '.json')
}

function Set-WorkbenchDatabaseLocation {
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$BranchRef,
        [Parameter(Mandatory)][string]$DatabasePath,
        [string]$StorageDirectory = (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'hosted-workbench/database-locations')
    )
    if (-not (Test-Path -LiteralPath $DatabasePath -PathType Leaf)) { throw 'Cannot record a missing workspace database.' }
    $locator = Get-WorkbenchDatabaseLocatorPath -RepositoryRoot $RepositoryRoot -BranchRef $BranchRef -StorageDirectory $StorageDirectory
    $null = New-Item -ItemType Directory -Path $StorageDirectory -Force
    $content = @{ databasePath = [IO.Path]::GetFullPath($DatabasePath) } | ConvertTo-Json -Compress
    [IO.File]::WriteAllText($locator, $content, [Text.UTF8Encoding]::new($false))
}

function Get-WorkbenchDatabaseLocation {
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$BranchRef,
        [string]$StorageDirectory = (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'hosted-workbench/database-locations')
    )
    $locator = Get-WorkbenchDatabaseLocatorPath -RepositoryRoot $RepositoryRoot -BranchRef $BranchRef -StorageDirectory $StorageDirectory
    if (-not (Test-Path -LiteralPath $locator -PathType Leaf)) { throw 'No initialized database location is recorded for this repository and branch.' }
    try {
        $record = [IO.File]::ReadAllText($locator) | ConvertFrom-Json
        if (@($record.PSObject.Properties.Name).Count -ne 1 -or $record.databasePath -isnot [string] -or
            [string]::IsNullOrWhiteSpace($record.databasePath) -or -not [IO.Path]::IsPathFullyQualified($record.databasePath)) { throw 'Invalid locator' }
        $path = [IO.Path]::GetFullPath($record.databasePath)
    } catch { throw 'The repository database location record is invalid.' }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'The recorded database for this repository and branch is missing.' }
    $path
}

Export-ModuleMember -Function Get-WorkbenchDatabaseLocation, Set-WorkbenchDatabaseLocation
