Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-WorkbenchInputFingerprint {
    param(
        [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{64}$')][string]$CatalogContentSha256,
        [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{64}$')][string]$ProtectedRulesContentSha256,
        [Parameter(Mandatory = $true)][Collections.IDictionary]$InventoryHashes
    )

    $sourceDefinitionIds = @($InventoryHashes.Keys)
    [Array]::Sort($sourceDefinitionIds, [StringComparer]::Ordinal)
    $fingerprintBuilder = [Text.StringBuilder]::new()
    $null = $fingerprintBuilder.Append($CatalogContentSha256).Append([char]0)
    $null = $fingerprintBuilder.Append($ProtectedRulesContentSha256).Append([char]0)
    foreach ($sourceDefinitionId in $sourceDefinitionIds) {
        $inventorySha256 = [string]$InventoryHashes[$sourceDefinitionId]
        if ($inventorySha256 -notmatch '^[0-9a-f]{64}$') {
            throw "Invalid source inventory hash: $sourceDefinitionId"
        }
        $null = $fingerprintBuilder.Append([string]$sourceDefinitionId).Append([char]0).Append($inventorySha256).Append([char]0)
    }
    $bytes = [Text.Encoding]::UTF8.GetBytes($fingerprintBuilder.ToString())
    try {
        return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
    }
    finally {
        [Array]::Clear($bytes, 0, $bytes.Length)
    }
}

Export-ModuleMember -Function Get-WorkbenchInputFingerprint
