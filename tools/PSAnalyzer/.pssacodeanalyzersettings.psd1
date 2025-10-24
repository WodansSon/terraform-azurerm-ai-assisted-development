@{
    # Severity levels to include
    Severity = @('Error', 'Warning')

    # Rules to exclude
    ExcludeRules = @(
        'PSAvoidGlobalVars'  # Global variables are used intentionally for script-wide state management
    )
}
