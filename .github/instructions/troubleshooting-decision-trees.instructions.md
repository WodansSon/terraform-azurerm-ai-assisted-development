---
applyTo: "internal/**/*.go"
description: Troubleshooting decision trees and diagnostic patterns for the Terraform AzureRM provider including common issues, debugging workflows, and resolution strategies.
---

# 🔧 Troubleshooting Decision Trees

<a id="🔧-troubleshooting-decision-trees"></a>

Troubleshooting decision trees and diagnostic patterns for the Terraform AzureRM provider including common issues, debugging workflows, and resolution strategies.

**Quick navigation:** <a href="#🚨-common-issues">🚨 Common Issues</a> | <a href="#🔍-debugging-workflows">🔍 Debugging Workflows</a> | <a href="#⚡-quick-fixes">⚡ Quick Fixes</a> | <a href="#🏗️-development-troubleshooting">🏗️ Development Troubleshooting</a>

<a id="🚨-common-issues"></a>

## 🚨 Common Issues

### Azure API Rate Limiting

**Symptoms:**
- HTTP 429 errors in logs
- Intermittent failures during resource operations
- Slow resource creation/update cycles

**Decision Tree:**
```text
Rule: evaluate in order and stop at the first matching condition.

- If subscription limits are the primary issue -> Review Azure portal quotas, verify service tier limits, and consider a subscription upgrade
- Else if polling or backoff behavior is the primary issue -> Prefer a service-specific custom poller for long-running status checks, tune poll interval or backoff deliberately, and use explicit retry limits only where retry behavior is still required
- Else -> Optimize API calls by batching operations where possible, caching frequently accessed data, and reducing unnecessary API calls
```

**Resolution Pattern:**
```text
- For provider implementation under `internal/**`, do not introduce a new generic `retryWithBackoff` helper as the default fix for repeated Azure polling.
- For long-running or repeated status-check behavior, prefer a service-specific custom poller instead of a manual retry loop or `StateChangeConf`-style polling helper.
- For rate limiting caused by request volume, reduce or batch API calls first and tune the poll interval or existing retry behavior deliberately.
```

**Custom Poller Pattern:**
```go
poller := custompollers.NewExamplePoller(client, id)
if err := pollers.PollUntilDone(ctx, poller); err != nil {
    return fmt.Errorf("waiting for completion: %+v", err)
}
```

### Resource State Drift

**Symptoms:**
- Terraform shows unexpected diffs on plan
- Resources appear modified outside Terraform
- Import operations fail with state mismatches

**Decision Tree:**
```text
Rule: evaluate in order and stop at the first matching condition.

- If the next step is to identify the drift source -> Check for manual Azure portal changes, other automation tools, Azure service auto-scaling, and provider version differences
- Else if the drift source is known and the next step is resolution -> Update Terraform configuration to match, import resources to sync state, apply changes to restore the desired state, or use a refresh-only plan to update state
- Else -> Prevent future drift by implementing Azure Policy controls, using resource locks where appropriate, establishing change management processes, and monitoring for unauthorized changes
```

### Authentication and Authorization Issues

**Symptoms:**
- HTTP 401/403 errors
- "Principal does not have access" errors
- Authentication timeouts

**Decision Tree:**
```text
Rule: evaluate in order and stop at the first matching condition.

- If credentials may be wrong or incomplete -> Check environment variables, validate the service principal, confirm tenant and subscription IDs, and test credential expiration
- Else if credentials are valid but access still fails -> Review Azure RBAC assignments, verify resource-level permissions, check API permissions for the service principal, and validate subscription access
- Else -> Test authentication with Azure CLI validation, minimal-permission scenarios, network connectivity checks, and conditional access policy checks
```

<a id="🔍-debugging-workflows"></a>

## 🔍 Debugging Workflows

### Step-by-Step Resource Debugging

**1. Information Gathering**
```bash
# Check Terraform version and provider version
terraform version

# Review resource configuration
terraform show -json | jq '.values.root_module.resources[] | select(.address == "azurerm_resource.example")'

# Check current state
terraform state show azurerm_resource.example
```

**2. Azure SDK Debugging**
```bash
# Enable detailed logging
$env:TF_LOG = "DEBUG"
$env:ARM_LOG_LEVEL = "DEBUG"

# Run targeted operation
terraform plan -target=azurerm_resource.example
```

**3. API Level Debugging**
```bash
# Use Azure CLI to test API directly
az rest --method GET --url "https://management.azure.com/subscriptions/{subscription-id}/resourceGroups/{rg}/providers/Microsoft.Service/resources/{name}?api-version=2023-01-01"
```

**4. Escalate When Logs Are Not Enough**
```text
- Prefer logging parsed resource ID structs rather than raw ID strings when tracing provider behavior.
- If TF_LOG output is insufficient, inspect traffic through an HTTPS debugging proxy.
- If request-level inspection still is not enough, attach a debugger such as delve rather than adding long-lived ad-hoc debug code.
```

### Network and Connectivity Issues

**Debugging Pattern:**
```text
Rule: evaluate in order and stop at the first matching condition.

- If basic connectivity is not yet confirmed -> Check the internet connection, verify DNS resolution, test Azure endpoints, and check proxy or firewall settings
- Else if basic connectivity works but Azure-specific access still fails -> Test the authentication endpoint, verify Azure API endpoints, check service-specific endpoints, and test from different networks
- Else -> Use provider-specific debugging by enabling TF_LOG=DEBUG, checking HTTP response codes, reviewing timeout settings, and testing with reduced concurrency
```

<a id="⚡-quick-fixes"></a>

## ⚡ Quick Fixes

### Common Error Resolution

**"Resource already exists" during creation:**
```bash
# Import existing resource
terraform import azurerm_resource.example /subscriptions/.../resourceGroups/.../providers/Microsoft.Service/resources/name

# Or force replacement
terraform apply -replace=azurerm_resource.example
```

**"Resource not found" during read:**
```bash
# Refresh state to detect deletion
terraform refresh

# Remove from state if manually deleted
terraform state rm azurerm_resource.example
```

**Schema validation errors:**
```hcl
# Check for deprecated arguments
# Review provider upgrade guides
# Validate argument types and values
```

### Performance Optimization

**Slow plan/apply operations:**
```bash
# Reduce parallelism
terraform plan -parallelism=1

# Target specific resources
terraform plan -target=azurerm_resource.example

# Use partial configuration
terraform plan -var-file=minimal.tfvars
```

<a id="🏗️-development-troubleshooting"></a>

## 🏗️ Development Troubleshooting

### Provider Development Issues

**Build Failures:**
```bash
# Check Go version compatibility
go version

# Update dependencies
go mod tidy

# Run specific tests
go test -v ./internal/services/servicename -run TestAccResourceName_basic
```

**Test Failures:**
```bash
# Run with detailed output
TF_ACC=1 go test -v ./internal/services/servicename -run TestAccResourceName_basic -timeout 60m

# Check for resource cleanup issues
# Review Azure credentials and permissions
# Verify test resource naming patterns
```

**Debugging Test Issues:**
```go
// Add debug logging to tests
t.Logf("Testing configuration: %s", config)

// Use acceptance.BuildTestData for consistent naming
data := acceptance.BuildTestData(t, "azurerm_resource", "test")

// Check for test isolation issues
// Verify resource group cleanup
// Review parallel test execution
```

**Official upstream debugging references:**
- `https://github.com/hashicorp/terraform-provider-azurerm/tree/main/contributing/topics/building-the-provider.md`
- `https://github.com/hashicorp/terraform-provider-azurerm/tree/main/contributing/topics/debugging-the-provider.md`
- `https://github.com/hashicorp/terraform-provider-azurerm/tree/main/contributing/topics/running-the-tests.md`

### CustomizeDiff Debugging

**Validation Logic Issues:**
```go
// Add logging to CustomizeDiff functions
func validateConfiguration(ctx context.Context, diff *schema.ResourceDiff, meta interface{}) error {
    log.Printf("[DEBUG] CustomizeDiff: validating configuration")

    // Test specific field combinations
    enabled := diff.Get("enabled").(bool)
    config := diff.Get("configuration").([]interface{})

    log.Printf("[DEBUG] enabled: %t, config length: %d", enabled, len(config))

    if enabled && len(config) == 0 {
        return fmt.Errorf("`configuration` is required when `enabled` is true")
    }

    return nil
}
```

**ForceNew Logic Issues:**
```go
// Debug ForceNew conditions
pluginsdk.ForceNewIfChange("field_name", func(ctx context.Context, old, new, meta interface{}) bool {
    log.Printf("[DEBUG] ForceNew check: old=%v, new=%v", old, new)

    shouldForceNew := old.(string) != new.(string)
    log.Printf("[DEBUG] ForceNew result: %t", shouldForceNew)

    return shouldForceNew
}),
```

### Azure API Integration Issues

**Client Configuration Problems:**
```go
// Debug client initialization
func debugClientSetup(metadata sdk.ResourceMetaData) {
    log.Printf("[DEBUG] Subscription ID: %s", metadata.Client.Account.SubscriptionId)
    log.Printf("[DEBUG] Client features: %+v", metadata.Client.Features)

    // Test client connectivity
    client := metadata.Client.ServiceName.ResourceClient
    // Make a lightweight API call to test
}
```

**Resource ID Parsing Issues:**
```go
// Debug resource ID parsing
id, err := parse.ServiceNameID(resourceId)
if err != nil {
    log.Printf("[DEBUG] Failed to parse resource ID '%s': %+v", resourceId, err)
    return fmt.Errorf("parsing Resource ID `%s`: %+v", resourceId, err)
}
log.Printf("[DEBUG] Parsed ID: %+v", id)
```
---
<a href="#🔧-troubleshooting-decision-trees">⬆️ Back to top</a>
