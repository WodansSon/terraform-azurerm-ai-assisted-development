[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$PayloadPath,
    [Parameter(Mandatory = $true)][string]$SchemaPath,
    [Parameter(Mandatory = $true)][string]$PromptPath,
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [Parameter(Mandatory = $true)][string]$Model,
    [Parameter(Mandatory = $true)][string]$ReasoningEffort
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$payload = Get-Content -LiteralPath $PayloadPath -Raw | ConvertFrom-Json
$relatedRule = @($payload.hostedRules | Where-Object { [string]$_.id -ceq 'IMPL-PATCH-001' })
$relationships = if ($relatedRule.Count -eq 1) {
    @([ordered]@{
        hostedRuleId = [string]$relatedRule[0].id
        relationship = 'partial-overlap'
        rationale = 'The deterministic fixture reports one material overlap for browser regression coverage.'
    })
}
else {
    throw 'Fixture payload did not include IMPL-PATCH-001 exactly once'
}
$result = [ordered]@{
    schemaVersion = 1
    ruleTextSha256 = [string]$payload.ruleTextSha256
    relationships = [object[]]@($relationships)
}
$resultJson = $result | ConvertTo-Json -Depth 10
if (-not ($resultJson | Test-Json -SchemaFile $SchemaPath -ErrorAction Stop)) {
    throw 'Fixture result does not satisfy the manual relationship schema'
}
[IO.File]::WriteAllText($OutputPath, ($resultJson + "`n"), [Text.UTF8Encoding]::new($false))
