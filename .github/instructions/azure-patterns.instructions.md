---
applyTo: "internal/**/*.go"
description: Azure-specific implementation patterns for the Terraform AzureRM provider including PATCH operations, CustomizeDiff patterns, and Azure SDK integration patterns.
---

# Azure-Specific Implementation Patterns

<a id="azure-specific-implementation-patterns"></a>

This file is a companion guide. Implementation compliance rules are defined by the implementation compliance contract:

- `.github/instructions/implementation-compliance-contract.instructions.md` (see `Canonical sources of truth (precedence)`).

Use this guide for Azure-specific implementation patterns such as PATCH behavior, CustomizeDiff patterns, and Azure SDK integration heuristics.
If this guide conflicts with the implementation contract, follow the contract and update this guide to re-align.

**Quick navigation:** <a href="#🔄-patch-operations">🔄 PATCH Operations</a> | <a href="#✅-customizediff-validation">✅ CustomizeDiff</a> | <a href="#🎯-schema-flattening">🎯 Schema Flattening</a> | <a href="#🚫-none-value-pattern">🚫 "None" Value Pattern</a> | <a href="#🔐-security-patterns">🔐 Security</a> | <a href="#🔄-state-management-with-dgetrawconfig">🔄 State Management</a> | <a href="#🏗️-progressive-code-simplification">🏗️ Progressive Code Simplification</a>

<a id="🔄-patch-operations"></a>

## 🔄 PATCH Operations

### Critical PATCH Behavior Understanding

**Azure Resource Manager PATCH Operations:**
Many Azure services use PATCH operations for resource updates, which have fundamentally different behavior from PUT operations:

- **PATCH preserves existing values** when fields are omitted from the request
- **PUT replaces the entire resource** with the provided configuration
- **Azure SDK nil filtering** removes `nil` values before sending requests to Azure
- **Residual state persistence** means previously enabled features remain active unless explicitly disabled

### PATCH Operation Pattern

```go
func ExpandPolicy(input []interface{}) *azuretype.Policy {
    // PATCH Operations Requirement: Always return a complete structure
    // with explicit enabled=false for disabled features to clear residual state

    // Define complete structure with all features disabled by default
    result := &azuretype.Policy{
        AutomaticFeature: &azuretype.AutomaticFeature{
            Enabled: pointer.To(false), // Explicit disable for PATCH
            // Include all required fields even when disabled
            RequiredSetting: pointer.To(azuretype.DefaultValue),
        },
        OptionalFeature: &azuretype.OptionalFeature{
            Enabled: pointer.To(false), // Explicit disable for PATCH
        },
    }

    // If no configuration, return everything disabled (clears residual state)
    if len(input) == 0 || input[0] == nil {
        return result
    }

    raw := input[0].(map[string]interface{})

    // Enable only explicitly configured features
    if automaticRaw, exists := raw["automatic_feature"]; exists {
        automaticList := automaticRaw.([]interface{})
        if len(automaticList) > 0 && automaticList[0] != nil {
            // Enable the feature and apply user configuration
            result.AutomaticFeature.Enabled = pointer.To(true)

            automatic := automaticList[0].(map[string]interface{})
            if setting := automatic["required_setting"].(string); setting != "" {
                result.AutomaticFeature.RequiredSetting = pointer.To(azuretype.Setting(setting))
            }
        }
        // If exists but empty block, feature remains disabled
    }
    // If not exists, feature remains disabled

    return result
}
```

### Documentation Requirements for PATCH Operations

```go
// PATCH Behavior Note: Azure VMSS uses PATCH operations which preserve existing values
// when fields are omitted. This means previously enabled policies will remain active
// unless explicitly disabled with enabled=false. Sending nil values gets filtered out
// by the Azure SDK, so Azure never receives disable commands. We must explicitly
// send enabled=false for all policies that should be disabled.
```

---
<a href="#azure-specific-implementation-patterns">⬆️ Back to top</a>

<a id="✅-customizediff-validation"></a>

## ✅ CustomizeDiff Validation

### Standard CustomizeDiff Pattern

**IMPORTANT**: CustomizeDiff import requirements depend on the implementation approach and are covered comprehensively in the main implementation guide.

**For complete import patterns, detailed examples, and implementation guidance, see:** [Implementation Guide - CustomizeDiff Import Requirements](./implementation-guide.instructions.md#customizediff-import-requirements)
### Boolean Comparison Best Practices in CustomizeDiff

**Simplified Boolean Expressions:**
```go
// PREFERRED - Simplified boolean expressions
pluginsdk.ForceNewIfChange("resilient_vm_creation_enabled", func(ctx context.Context, old, new, meta interface{}) bool {
    fieldExists := !d.GetRawConfig().GetAttr("resilient_vm_creation_enabled").IsNull()
    return fieldExists && old.(bool) && !new.(bool)
}),

// FORBIDDEN - Verbose expressions that trigger gosimple linting errors
return fieldExists && old.(bool) == true && new.(bool) == false
```

**Key Principles:**
- Use direct boolean expressions: `old.(bool) && !new.(bool)`
- Leverage Go's boolean semantics: `bool` values can be used directly in logical expressions
- Comply with linting standards: Simplified expressions pass gosimple and other Go linting tools
- Maintain readability: Shorter expressions are easier to understand and maintain

### Azure-Specific CustomizeDiff Use Cases

Azure resources have unique validation requirements that CustomizeDiff functions must enforce:

- **SKU validation**: Ensure Azure SKU combinations are valid
- **Location constraints**: Validate region-specific feature availability
- **Resource dependencies**: Check Azure resource prerequisite relationships
- **API version compatibility**: Ensure feature combinations match Azure API versions
- **Performance tier validation**: Validate Azure performance tier constraints
- **Field conditional validation**: Validate field combinations based on Azure API constraints

**For comprehensive multi-function CustomizeDiff patterns and complex validation examples, see:** [Implementation Guide - CustomizeDiff Import Requirements](./implementation-guide.instructions.md#customizediff-import-requirements)

### AZURE-PATTERN-001: Prefer `GetRawConfig()` when `CustomizeDiff` must distinguish configured values from known-after-apply or zero values

- Rule: In `CustomizeDiff`, prefer `GetRawConfig()` over `d.Get()` or decoded zero values when validation must distinguish unset fields from known-after-apply or Go zero values.
- Rule: Use this pattern for cross-field validation where unknown values would otherwise collapse to zero values and trigger false positives.
- **Provenance**: Published upstream standard.
- **Evidence**:
    - Upstream contributor guidance in `hashicorp/terraform-provider-azurerm/contributing/topics/best-practices.md` under `Consider the use of GetRawConfig() in CustomizeDiff to handle known-after-apply values`
    - That guidance uses `GetRawConfig()` as the preferred pattern when `d.Get()` or decoded values would make unknowns look unset

### Zero Value Validation Pattern

**Critical Pattern for Optional Fields with Go Zero Values:**

When validating optional fields in CustomizeDiff functions, Go's zero value behavior can cause false validation errors. An unset field defaults to its Go zero value (`0` for integers, `false` for booleans, `""` for strings), which validation logic may incorrectly interpret as an explicitly set value.

**🚨 MANDATORY: AI Schema Definition Verification Before Field Validation Suggestions**

**BEFORE the AI suggests ANY empty/exists checks on fields, the AI MUST:**

1. **Examine schema definition** to determine if field is:
   - **Required**: Field must have a value, AI should suggest `diff.Get()` or direct access
   - **Optional**: Field may be unset, AI should suggest `GetRawConfig().IsNull()` check first
   - **Optional+Computed**: Field may be unset or computed by Azure, AI should suggest distinguishing user-configured vs Azure values

2. **AI should suggest appropriate validation pattern** based on schema type:
   ```go
   // STEP 1: AI examines schema definition first
   "field_name": {
       Type:     pluginsdk.TypeString,
       Optional: true,  // This determines AI's suggested validation approach
       Computed: true,  // Optional+Computed requires special AI guidance
   }

   // STEP 2: AI Decision Tree - suggests appropriate validation pattern
   ```

   **Required Fields** → AI suggests direct access:
   ```go
   // Typed Resource Implementation
   var model ServiceNameModel
   if err := metadata.Decode(&model); err != nil {
       return fmt.Errorf("decoding: %+v", err)
   }
   // Use model.FieldName directly - Required fields guaranteed to have values

   // Untyped Resource Implementation
   value := diff.Get("field_name").(string)
   // Use value directly - Required fields guaranteed to have values
   ```

   **Optional Fields** → AI suggests checking explicit configuration:
   ```go
   // Typed Resource Implementation
   var model ServiceNameModel
   if err := metadata.Decode(&model); err != nil {
       return fmt.Errorf("decoding: %+v", err)
   }
   // Check raw config to distinguish user-set vs default values
   if !metadata.ResourceData.GetRawConfig().GetAttr("field_name").IsNull() {
       // Validate model.FieldName only if user explicitly configured it
   }

   // Untyped Resource Implementation
   if !diff.GetRawConfig().GetAttr("field_name").IsNull() {
       value := diff.Get("field_name").(string)
       // AI suggests validating only if user explicitly set the field
   }
   ```

   **Optional+Computed Fields** → AI suggests user vs Azure value distinction:
   ```go
   // Typed Resource Implementation
   var model ServiceNameModel
   if err := metadata.Decode(&model); err != nil {
       return fmt.Errorf("decoding: %+v", err)
   }
   // Distinguish user-configured vs Azure-computed values
   if !metadata.ResourceData.GetRawConfig().GetAttr("field_name").IsNull() {
       // Validate model.FieldName only for user-configured values
   }
   // Skip validation for Azure-computed values

   // Untyped Resource Implementation
   if !diff.GetRawConfig().GetAttr("field_name").IsNull() {
       value := diff.Get("field_name").(string)
       // AI suggests validating user-configured values only
   }
   // AI suggests skipping validation for Azure-computed values
   ```

3. **AI Schema Analysis Checklist Before Code Suggestions:**
   - [ ] Examined field schema type (Required/Optional/Optional+Computed)
   - [ ] Suggested appropriate validation method based on schema type
   - [ ] Avoided suggesting `GetRawConfig()` for Required fields (unnecessary overhead)
   - [ ] Avoided suggesting false validation errors from Go zero values
   - [ ] Suggested validation logic only for explicitly configured values

**Key Implementation Pattern:**
- **Use `GetRawConfig()`**: Access the raw configuration to check for null values
- **Check `.IsNull()`**: Distinguish between unset fields and zero values
- **Validation Logic**: Only validate fields that were explicitly configured by users
- **Error Prevention**: Prevents false positive validation errors from Go zero values
- **Azure API Alignment**: Ensures validation matches actual Azure service behavior

**Common Use Cases:**
- **Optional integer fields**: rank, timeout_seconds, priority, weight
- **Optional boolean fields**: enabled, allow_public_access, force_destroy
- **Optional string fields**: When empty string (`""`) is not a valid configuration
- **Optional numeric configurations**: port numbers, retry counts, threshold values
- **Azure resource constraints**: SKU-dependent validation, region-specific limits

**When NOT to Use `GetRawConfig()` for Zero Value Validation:**
- **Required fields**: Always use `diff.Get()` since required fields must have values
- **Typed resource implementations**: Use `metadata.Decode()` patterns instead of raw config access
- **Simple field access**: When you need the value regardless of how it was set
- **Performance-critical paths**: Raw config access has overhead, use sparingly

**For comprehensive `GetRawConfig()` usage guidance, see:** <a href="#🔄-state-management-with-dgetrawconfig">State Management with d.GetRawConfig()</a>

### Field Removal ForceNew Pattern

**Critical Pattern for Fields Removed from Configuration Requiring Resource Recreation:**

When Azure resources have irreversible configuration changes (like enabling security policies that cannot be disabled), removing the field from Terraform configuration should trigger resource recreation. This requires using `CustomizeDiffShim` with both `SetNew()` and `ForceNew()` to work together.

**Why Both SetNew and ForceNew Are Required:**
- **SetNew()**: Creates a detectable state change in Terraform's plan showing the field going from `true` → `false`
- **ForceNew()**: Triggers resource recreation when this change occurs
- **Plan Visibility**: Terraform must show the field value change to justify the ForceNew action to users
- **Test Framework**: Acceptance tests require visible state changes to validate ForceNew behavior

**Implementation Pattern:**
```go
pluginsdk.CustomizeDiffShim(func(ctx context.Context, diff *pluginsdk.ResourceDiff, v interface{}) error {
    var featureExists, policyExists bool

    // Check if fields exist in the raw configuration (not computed/inferred values)
    if rawConfig := diff.GetRawConfig(); !rawConfig.IsNull() {
        featureExists = !rawConfig.AsValueMap()["irreversible_feature_enabled"].IsNull()
        policyExists = !rawConfig.AsValueMap()["security_policy_enabled"].IsNull()
    }

    // Only apply ForceNew logic during updates (not during initial creation)
    if diff.Id() != "" {
        // Handle irreversible_feature_enabled field removal
        if !featureExists {
            // Check if field was previously enabled in state
            if old, _ := diff.GetChange("irreversible_feature_enabled"); old.(bool) {
                // CRITICAL: SetNew makes the change visible in Terraform plan
                // This shows users: irreversible_feature_enabled: true → false
                if err := diff.SetNew("irreversible_feature_enabled", false); err != nil {
                    return fmt.Errorf("setting `irreversible_feature_enabled` to `false`: %+v", err)
                }
                // ForceNew triggers resource recreation since Azure cannot disable this feature
                return diff.ForceNew("irreversible_feature_enabled")
            }
        }

        // Handle security_policy_enabled field removal (same pattern)
        if !policyExists {
            if old, _ := diff.GetChange("security_policy_enabled"); old.(bool) {
                // Same pattern: make change visible then force recreation
                if err := diff.SetNew("security_policy_enabled", false); err != nil {
                    return fmt.Errorf("setting `security_policy_enabled` to `false`: %+v", err)
                }
                return diff.ForceNew("security_policy_enabled")
            }
        }
    }

    return nil
}),
```

**Azure Use Cases:**
- **VM Scale Set Resiliency Policies**: Cannot be disabled once enabled
- **Security Features**: Irreversible security configurations
- **Compliance Settings**: Audit policies that cannot be downgraded
- **Performance Tiers**: Service levels that require recreation to reduce

**Key Requirements:**
- **Irreversible Changes**: Only use for Azure features that cannot be disabled once enabled
- **Raw Config Detection**: Use `GetRawConfig().AsValueMap()` to detect field presence vs absence in configuration
- **Update-Only Logic**: Check `diff.Id() != ""` to ensure logic only applies to existing resources, not during creation
- **State Visibility**: SetNew must be called before ForceNew to create visible plan entry
- **Error Handling**: SetNew errors should be caught and wrapped with descriptive context
- **Test Validation**: Tests must verify both the state change and ForceNew trigger

**Common Mistakes to Avoid:**
- **ForceNew without SetNew**: Plan won't show why recreation is needed - users will be confused by ForceNew without visible changes
- **SetNew without ForceNew**: State changes but resource doesn't recreate when Azure constraints require it
- **Missing Error Handling**: SetNew failures can break plan generation if not properly handled
- **Wrong Field Detection**: Use `GetRawConfig().AsValueMap()[field].IsNull()` to detect field removal, not `diff.Get()`
- **Creation vs Update**: Apply logic only during updates (`diff.Id() != ""`), not during initial resource creation

**For comprehensive `GetRawConfig()` usage guidance, see:** <a href="#🔄-state-management-with-dgetrawconfig">State Management with d.GetRawConfig()</a>

---
<a href="#azure-specific-implementation-patterns">⬆️ Back to top</a>

<a id="🎯-schema-flattening"></a>

## 🎯 Schema Flattening

### When to Apply Schema Flattening

Schema flattening should be considered when Azure APIs contain unnecessary wrapper structures that don't provide value to Terraform users:

- **Single-purpose wrappers**: Remove intermediate blocks that only contain a single array or enable flag
- **Azure API convenience structures**: Eliminate wrapper objects that exist purely for API organization
- **User experience improvement**: Flatten when it simplifies configuration without losing functionality
- **Logical grouping preservation**: Maintain nested structures when they provide logical organization

### Schema Flattening Example

**Before Flattening (Complex Structure):**
```go
resource "azurerm_cdn_frontdoor_profile" "example" {
  name = "example"

  log_scrubbing {
    enabled = true

    scrubbing_rule {
      match_variable = "QueryStringArgNames"
    }
  }
}
```

**After Flattening (Simplified Structure):**
```go
resource "azurerm_cdn_frontdoor_profile" "example" {
  name = "example"

  log_scrubbing_rule {
    match_variable = "QueryStringArgNames"
  }
}
```

### Implementation Pattern for Schema Flattening

```go
// Schema definition - direct access to the meaningful configuration
"log_scrubbing_rule": {
    Type:     pluginsdk.TypeSet,
    MaxItems: 3,
    Optional: true,
    Elem: &pluginsdk.Resource{
        Schema: map[string]*pluginsdk.Schema{
            "match_variable": {
                Type:     pluginsdk.TypeString,
                Required: true,
                ValidateFunc: validation.StringInSlice(
                    profiles.PossibleValuesForScrubbingRuleEntryMatchVariable(),
                    false),
            },
        },
    },
},

// Expand function - handle the wrapper structure internally
func expandCdnFrontDoorProfileLogScrubbing(input []interface{}) *profiles.ProfileLogScrubbing {
    if len(input) == 0 {
        // When no rules configured, set to disabled (following "None" pattern)
        return &profiles.ProfileLogScrubbing{
            State:          pointer.To(profiles.ProfileScrubbingStateDisabled),
            ScrubbingRules: nil,
        }
    }

    // When rules are present, always enable the feature
    return &profiles.ProfileLogScrubbing{
        State:          pointer.To(profiles.ProfileScrubbingStateEnabled),
        ScrubbingRules: expandScrubbingRules(input),
    }
}

// Flatten function - hide wrapper complexity from users
func flattenCdnFrontDoorProfileLogScrubbing(input *profiles.ProfileLogScrubbing) []interface{} {
    if input == nil || pointer.From(input.State) == profiles.ProfileScrubbingStateDisabled {
        // When disabled, return empty list (following "None" pattern)
        return make([]interface{}, 0)
    }

    // Return only the meaningful rules, hiding the wrapper
    return flattenScrubbingRules(input.ScrubbingRules)
}
```
---
<a href="#azure-specific-implementation-patterns">⬆️ Back to top</a>

<a id="🚫-none-value-pattern"></a>

## 🚫 "None" Value Pattern

### The "None" Value Pattern

### AZURE-PATTERN-002: Convert Azure `None`-style defaults through omission rather than exposing them as first-class user values

- Rule: When an Azure API uses `None`, `Off`, or `Default` to express the default state, prefer omission/null in Terraform and convert that omission to the Azure value during expand/flatten.
- Rule: Do not require practitioners to configure `None`-style values explicitly when omission already expresses the default behavior.
- **Provenance**: Published upstream standard.
- **Evidence**:
    - Upstream contributor guidance in `hashicorp/terraform-provider-azurerm/contributing/topics/schema-design-considerations.md` under `The None value or similar`
    - That guidance says omission should map to the API default rather than exposing `None`, `Off`, or `Default` directly

Many Azure APIs accept values like None, Off, or Default as default values. The provider is moving away from exposing these values directly to users, instead leveraging Terraform's native null handling by allowing fields to be omitted.

**Modern Approach (Preferred):**
```go
// Schema excludes the "None" value - users omit the field instead
"shutdown_on_idle": {
    Type:     pluginsdk.TypeString,
    Optional: true,
    ValidateFunc: validation.StringInSlice([]string{
        string(azureapi.ShutdownOnIdleModeUserAbsence),
        string(azureapi.ShutdownOnIdleModeLowUsage),
        // Note: "None" value exists but is handled in Create/Update and Read functions
        // NOT exposed in validation
    }, false),
},
```

**Typed Resource Implementation:**
```go
func (r ServiceResource) Create() sdk.ResourceFunc {
    return sdk.ResourceFunc{
        Timeout: 30 * time.Minute,
        Func: func(ctx context.Context, metadata sdk.ResourceMetaData) error {
            var model ServiceNameModel
            if err := metadata.Decode(&model); err != nil {
                return fmt.Errorf("decoding: %+v", err)
            }

            // Default to "None" if user did not specify a value
            properties := azureapi.ServiceProperties{
                ShutdownOnIdle: pointer.To(string(azureapi.ShutdownOnIdleModeNone)),
            }
            if model.ShutdownOnIdle != "" {
                properties.ShutdownOnIdle = pointer.To(model.ShutdownOnIdle)
            }

            // ...continue with resource creation
            return nil
        },
    }
}

func (r ServiceResource) Read() sdk.ResourceFunc {
    return sdk.ResourceFunc{
        Timeout: 5 * time.Minute,
        Func: func(ctx context.Context, metadata sdk.ResourceMetaData) error {
            // ...retrieve resource from Azure

            model := ServiceModel{}

            // Only set value in state if it is not "None"
            if props.ShutdownOnIdle != nil && *props.ShutdownOnIdle != string(azureapi.ShutdownOnIdleModeNone) {
                model.ShutdownOnIdle = *props.ShutdownOnIdle
            }
            // If Azure returns "None", field remains empty in Terraform state

            return metadata.Encode(&model)
        },
    }
}
```

---
<a href="#azure-specific-implementation-patterns">⬆️ Back to top</a>

<a id="🔐-security-patterns"></a>

## 🔐 Security Patterns

### Credential and Secret Management

**Never Log Sensitive Information:**
```go
// GOOD - No sensitive data in logs
metadata.Logger.Infof("Creating Storage Account %s", id.StorageAccountName)
log.Printf("[DEBUG] Configuring network rules for %s", id)

// FORBIDDEN - Sensitive data in logs
log.Printf("[DEBUG] Connection string: %s", connectionString) // Never log connection strings
metadata.Logger.Debugf("Client secret: %s", clientSecret)     // Never log secrets
log.Printf("[DEBUG] SAS token: %s", sasToken)                 // Never log tokens
```

**Secure Environment Variable Handling:**
```go
func validateTestCredentials() error {
    requiredVars := []string{
        "ARM_SUBSCRIPTION_ID",
        "ARM_CLIENT_ID",
        "ARM_CLIENT_SECRET",
        "ARM_TENANT_ID",
    }

    for _, envVar := range requiredVars {
        if value := os.Getenv(envVar); value == "" {
            return fmt.Errorf("required environment variable %s is not set", envVar)
        }
    }
    return nil
}
```

### Input Validation and Sanitization

**Prevent Injection Attacks:**
```go
func ValidateAzureResourceName(v interface{}, k string) (warnings []string, errors []error) {
    value := v.(string)

    // Validate length
    if len(value) < 1 || len(value) > 64 {
        errors = append(errors, fmt.Errorf("property %s must be between 1 and 64 characters, got %d", k, len(value)))
        return warnings, errors
    }

    // Validate allowed characters only (prevent injection)
    allowedPattern := regexp.MustCompile(`^[a-zA-Z0-9-_]+$`)
    if !allowedPattern.MatchString(value) {
        errors = append(errors, fmt.Errorf("property %s can only contain alphanumeric characters, hyphens, and underscores", k))
        return warnings, errors
    }

    // Azure Storage Account specific reserved names
    reservedNames := []string{"admin", "root", "system", "default"}
    for _, reserved := range reservedNames {
        if strings.EqualFold(value, reserved) {
            errors = append(errors, fmt.Errorf("property `%s` cannot use reserved name `%s`", k, reserved))
            return warnings, errors
        }
    }

    return warnings, errors
}
```
---
<a href="#azure-specific-implementation-patterns">⬆️ Back to top</a>

<a id="🔄-state-management-with-dgetrawconfig"></a>

## 🔄 State Management with d.GetRawConfig()

### When to Use `d.GetRawConfig()` vs `d.Get()`

**IMPORTANT**: This pattern is only available in untyped Plugin SDK resource implementations.

`d.GetRawConfig()` should be used in specific scenarios where you need to distinguish between user-configured values and computed/default values.

**Appropriate Use Cases:**
```go
// 1. Detecting if a user explicitly set a value vs using a default
func resourceServiceNameUpdate(ctx context.Context, d *pluginsdk.ResourceData, meta interface{}) error {
    client := meta.(*clients.Client).ServiceName.ResourceClient

    id, err := parse.ServiceNameID(d.Id())
    if err != nil {
        return err
    }

    parameters := serviceapi.UpdateParameters{
        Name: d.Get("name").(string),
    }

    // Check if user explicitly configured the setting
    if raw := d.GetRawConfig().GetAttr("timeout_seconds"); !raw.IsNull() {
        // User explicitly set this value, use it
        timeoutValue := d.Get("timeout_seconds").(int)
        parameters.TimeoutSeconds = &timeoutValue
    }
    // If raw is null, don't send timeout_seconds parameter to Azure API
    // This allows Azure to use its service default

    if err := client.UpdateThenPoll(ctx, *id, parameters); err != nil {
        return fmt.Errorf("updating %s: %+v", *id, err)
    }

    return nil
}

// 2. Handling optional complex blocks that should be omitted when not configured
func resourceServiceNameCreate(ctx context.Context, d *pluginsdk.ResourceData, meta interface{}) error {
    // ... standard setup code

    parameters := serviceapi.CreateParameters{
        Name:     name,
        Location: location,
    }

    // Only include advanced_config if user explicitly configured it
    if raw := d.GetRawConfig().GetAttr("advanced_config"); !raw.IsNull() {
        parameters.AdvancedConfig = pointer.To(expandAdvancedConfig(d.Get("advanced_config").([]interface{})))
    }
    // If raw is null, don't include AdvancedConfig in API call

    // ... continue with resource creation
}
```

---
<a href="#azure-specific-implementation-patterns">⬆️ Back to top</a>

<a id="🏗️-progressive-code-simplification"></a>

## 🏗️ Progressive Code Simplification

### When Complex Logic Needs Simplification

When implementing Azure resource expand/flatten functions, especially for PATCH operations, complex conditional logic can often be simplified through strategic refactoring.

**Step 2: Define Complete Disabled Structure (Recommended)**
```go
func ExpandPolicy(input []interface{}) *azuretype.Policy {
    // Define complete result with all features disabled by default
    result := &azuretype.Policy{
        FeatureA: &azuretype.FeatureA{
            Enabled: pointer.To(false),                        // Disabled by default
            RequiredField: pointer.To(azuretype.DefaultValue), // Required even when disabled
        },
        FeatureB: &azuretype.FeatureB{
            Enabled: pointer.To(false), // Disabled by default
        },
    }

    // If no input, return everything disabled
    if len(input) == 0 || input[0] == nil {
        return result
    }

    raw := input[0].(map[string]interface{})

    // Simple field flipping logic - enable only what's configured
    if featureARaw, exists := raw["feature_a"]; exists {
        featureAList := featureARaw.([]interface{})
        if len(featureAList) > 0 && featureAList[0] != nil {
            // Enable the feature and apply user configuration
            result.FeatureA.Enabled = pointer.To(true)
            // Apply other configuration...
        }
    }

    if featureBEnabled, exists := raw["feature_b_enabled"]; exists {
        result.FeatureB.Enabled = pointer.To(featureBEnabled.(bool))
    }

    return result
}
```

**Key Simplification Principles:**
1. **Define end state first** - Create complete structure with desired defaults
2. **Use simple field flipping** - Change only what needs to change based on input
3. **Eliminate conditional returns** - Single return path reduces complexity
4. **Extract common patterns** - Use variables for repeated structures
5. **Start with working code** - Simplify incrementally, don't rewrite from scratch

## 📚 Related Specialized Guidance (On-Demand)

### **Schema & Structure**
- 📐 **Schema Patterns**: [schema-patterns.instructions.md](./schema-patterns.instructions.md) - Azure schema design, validation patterns

### **Quality & Evolution**
- 📋 **Code Clarity**: [code-clarity-enforcement.instructions.md](./code-clarity-enforcement.instructions.md) - Code quality standards
- 🔄 **Migration Guide**: [migration-guide.instructions.md](./migration-guide.instructions.md) - Azure API evolution patterns

---
<a href="#azure-specific-implementation-patterns">⬆️ Back to top</a>
