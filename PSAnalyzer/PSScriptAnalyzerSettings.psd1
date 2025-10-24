@{
    # Severity levels to include
    Severity = @('Error', 'Warning')

    # Rules to exclude
    ExcludeRules = @(
        'PSAvoidGlobalVars',                             # Intentional use for script-wide state
        'PSAvoidUsingWriteHost',                         # Acceptable for interactive installer scripts
        'PSUseShouldProcessForStateChangingFunctions',   # Not applicable for our use case
        'PSReviewUnusedParameter',                       # Parameters kept for API compatibility/future use
        'PSAvoidUsingEmptyCatchBlock',                   # Intentional for error suppression in non-critical operations
        'PSUseDeclaredVarsMoreThanAssignments'           # Variables kept for debugging/future use
    )

    # Include default rules from PSGallery
    IncludeDefaultRules = $true
}
