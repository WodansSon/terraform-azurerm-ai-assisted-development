---
applyTo: "internal/**/*_test.go"
description: Testing guidelines for Terraform AzureRM provider Go files - test execution protocols, patterns, and Azure-specific considerations.
---

# 🧪 Testing Guidelines


This file is a companion guide. Testing compliance rules are defined by the testing compliance contract:

- `.github/instructions/testing-compliance-contract.instructions.md` (see `Canonical sources of truth (precedence)`).

Use this guide for testing patterns and Azure-specific testing heuristics.
Use the `acceptance-testing` skill for acceptance-test execution workflow, environment prerequisites, and failure triage.
If this guide conflicts with the testing contract, follow the testing contract and update this guide to re-align.


<a id="🧪-efficient-testing-with-importstep"></a>

## 🧪 Efficient Testing with ImportStep

When using `data.ImportStep()` in acceptance tests, field validation checks are often redundant because ImportStep automatically validates that the resource can be imported and that all field values match between the configuration and the imported state.

**Recommended Pattern - ExistsInAzure Check:**
```go
func TestAcc{{RESOURCE_NAME}}_basic(t *testing.T) {
    data := acceptance.BuildTestData(t, "azurerm_{{RESOURCE_SLUG}}", "test")
    r := {{RESOURCE_HELPER}}{}

    data.ResourceTest(t, r, []acceptance.TestStep{
        {
            Config: r.basic(data),
            Check: acceptance.ComposeTestCheckFunc(
                check.That(data.ResourceName).ExistsInAzure(r),
                // Additional checks only when ImportStep cannot verify specific behavior
            ),
        },
        data.ImportStep(), // Validates all configured field values automatically
    })
}
```

**Best Practices:**
- **ImportStep provides comprehensive validation**: Reduces need for explicit field checks
- **Focus on ExistsInAzure**: Essential for verifying resource creation and existence
- **Add specific checks when needed**: For computed fields, complex behaviors, or edge cases
- **Document rationale**: Explain when additional checks add value beyond ImportStep

---

<a id="🧪-test-types"></a>

## 🧪 Test Types

**Unit Tests:**
- Place in same package with `_test.go` suffix
- Test utility functions, parsers, validators
- Use table-driven patterns
- No Azure credentials required

**Acceptance Tests:**
- Test against real Azure APIs with live credentials
- Package naming: `package servicename_test` (external test package)
- Test CRUD operations, imports, and state management
- Use acceptance testing framework

### Naming Conventions

**Unit Tests:** `TestFunctionName_Scenario_ExpectedOutcome`
- Example: `TestParse{{RESOURCE_ID_TYPE}}_ValidID_ReturnsCorrectComponents`

**Acceptance Tests:** `TestAccResourceName_scenario`
- Example: `TestAcc{{RESOURCE_NAME}}_basic`
- Example: `TestAcc{{RESOURCE_NAME}}_requiresImport`
- Use underscores to separate logical components: `TestAccResourceName_featureGroup_specificScenario`
- Example: `TestAcc{{RESOURCE_NAME}}_{{FEATURE_GROUP}}_{{SCENARIO_NAME}}`

**Test Helper Functions:** Use camelCase (Go convention for unexported functions)
- Example: `{{featureGroup}}{{scenarioName}}(data acceptance.TestData) string`
- Example: `with{{NestedBlockName}}(data acceptance.TestData) string`
- Example: `basicConfiguration(data acceptance.TestData) string`

**Key Distinction:**
- **Test function names**: Use underscores for logical separation (`_featureGroup_scenario`)
- **Helper function names**: Use camelCase following Go naming conventions for unexported functions

### Config Helper Composition

- In helper functions that return `fmt.Sprintf(...)` acceptance-test configuration, pass one-use nested helper calls directly into `fmt.Sprintf(...)` rather than assigning locals like `template := r.template(data)` or `config := r.basic(data)` only to forward them once.
- Keep a local variable only when the nested helper result is reused, transformed, or clearly improves readability.

### Embedded Terraform Formatting

- In embedded Terraform configuration blocks inside `*_test.go` files, use two spaces for Terraform configuration indentation and never tabs.
- Preserve the surrounding heredoc formatting when editing an existing acceptance-test config block.
- If editor tab rendering makes indentation ambiguous, use the examples below as the source of truth for what valid and invalid embedded Terraform formatting look like.

**Recommended Pattern:**
```go
func (r ExampleResource) basic(data acceptance.TestData) string {
        return fmt.Sprintf(`
resource "azurerm_example" "test" {
  name                = "acctest-example-%d"
  resource_group_name = azurerm_resource_group.test.name
  location            = azurerm_resource_group.test.location

  tags = {
    environment = "acctest"
  }
}
`, data.RandomInteger)
}
```

**Invalid Pattern:**
```go
func (r ExampleResource) basic(data acceptance.TestData) string {
    return fmt.Sprintf(`
resource "azurerm_example" "test" {
<TAB>name = "acctest-example-%d"
<TAB>resource_group_name  = azurerm_resource_group.test.name
     location<TAB><TAB>   = azurerm_resource_group.test.location

<TAB>tags = {
<TAB>  environment = "acctest"
<TAB>}
}
`, data.RandomInteger)
}
```

- In the invalid example, `<TAB>` represents a literal tab character. That sample intentionally mixes tab-prefixed lines, space-indented lines, and tabs-plus-spaces within a single configuration line so formatting drift stays obvious even in editors that render tabs with a Terraform-sized tab width.

### Helper Struct Naming

- In acceptance test files under `internal/services/**`, use one canonical helper struct name per Terraform resource or data source.
- If the surface already has an established canonical helper type, keep using that same type across all related acceptance tests and generated identity tests.
- For new surfaces without an established helper type, prefer `ToCamel(x)Resource` for resources and `ToCamel(x)DataSource` for data sources.
- Keep that same helper type across all acceptance test variants for the same Terraform surface, not just the main file: resource tests, list tests, identity-related tests, and any other helper-instantiating tests should all use the same canonical type.
- Generated identity tests under `*_identity_gen_test.go` should use that same helper type directly rather than introducing a separate `SomethingIdentityResource` helper, alias, or wrapper.
- The rule matters because the canonical helper types for a Terraform surface must remain the single source of truth, and generated identity tests must use those same types directly so generated files do not churn.

### Go Testing Patterns

**Table-Driven Tests:**
```go
func TestParseResourceID(t *testing.T) {
    testCases := []struct {
        name        string
        input       string
        expected    ResourceID
        shouldError bool
    }{
        {
            name:     "valid resource ID",
            input:    "/subscriptions/12345/resourceGroups/rg1/providers/Microsoft.Service/resources/resource1",
            expected: ResourceID{SubscriptionID: "12345", ResourceGroup: "rg1", Name: "resource1"},
            shouldError: false,
        },
        {
            name:        "invalid resource ID",
            input:       "invalid-id",
            expected:    ResourceID{},
            shouldError: true,
        },
    }

    for _, tc := range testCases {
        t.Run(tc.name, func(t *testing.T) {
            result, err := ParseResourceID(tc.input)

            if tc.shouldError {
                if err == nil {
                    t.Errorf("expected error but got none")
                }
                return
            }

            if err != nil {
                t.Errorf("unexpected error: %v", err)
                return
            }

            if !reflect.DeepEqual(result, tc.expected) {
                t.Errorf("expected %+v, got %+v", tc.expected, result)
            }
        })
    }
}
```

**Assertion Patterns:**
```go
// Use testify assertions for cleaner test code
func TestResourceValidation(t *testing.T) {
    require := require.New(t)
    assert := assert.New(t)

    // Test setup
    resource := createTestResource()

    // Assertions
    require.NotNil(resource)
    assert.Equal("expected-value", resource.Name)
    assert.True(resource.Enabled)
    assert.Contains(resource.Tags, "environment")
}
```

---

<a id="⚡-essential-test-patterns"></a>

## ⚡ Essential Test Patterns

**Basic Resource Test:**
```go
func TestAccResourceName_basic(t *testing.T) {
    data := acceptance.BuildTestData(t, "azurerm_resource_name", "test")
    r := ResourceNameResource{}

    data.ResourceTest(t, r, []acceptance.TestStep{
        {
            Config: r.basic(data),
            Check: acceptance.ComposeTestCheckFunc(
                check.That(data.ResourceName).ExistsInAzure(r),
            ),
        },
        data.ImportStep(), // Validates all field values automatically
    })
}
```

**RequiresImport Test:**
```go
func TestAccResourceName_requiresImport(t *testing.T) {
    data := acceptance.BuildTestData(t, "azurerm_resource_name", "test")
    r := ResourceNameResource{}
    data.ResourceTest(t, r, []acceptance.TestStep{
        {
            Config: r.basic(data),
            Check: acceptance.ComposeTestCheckFunc(
                check.That(data.ResourceName).ExistsInAzure(r),
            ),
        },
        data.RequiresImportErrorStep(r.requiresImport),
    })
}
```

### **Azure Testing Best Practices**
- Be aware that acceptance tests create real Azure resources
- Ensure Azure credentials are properly configured when needed
- Consider costs and cleanup requirements for acceptance tests
- Unit tests are safe and can be run without Azure resources

**These practices help maintain awareness of Azure resource implications while enabling effective testing workflows.**

---

<a id="✅-customizediff-testing"></a>

## ✅ CustomizeDiff Testing

**Why Important:**
- CustomizeDiff prevents invalid Azure API calls
- Enforces Azure service field combination requirements
- Provides clear error messages before resource operations

**Recommended Test Coverage:**
- **Error scenarios**: Test invalid field combinations with `ExpectError: regexp.MustCompile()`
- **Success scenarios**: Usually covered by other test cases (e.g., `basic`, `update`, and `complete`)
- **Edge cases**: Test boundary conditions and Azure service constraints

**CustomizeDiff Test Pattern:**
```go
func TestAccServiceName_featureName_customizeDiffValidation(t *testing.T) {
    data := acceptance.BuildTestData(t, "azurerm_service_name", "test")
    r := ServiceNameResource{}

    data.ResourceTest(t, r, []acceptance.TestStep{
        {
            Config:      r.invalidConfiguration(data),
            ExpectError: regexp.MustCompile("`configuration` is required when `enabled` is `true`"),
        },
    })
}
```

CustomizeDiff validations are essential for enforcing Azure API constraints and preventing invalid configurations. Testing these validations provides comprehensive coverage of both success and failure scenarios.

### Why CustomizeDiff Testing is Important

**Azure API Constraint Enforcement:**
- CustomizeDiff validations prevent invalid API calls that would fail at runtime
- They enforce Azure service-specific field combination requirements
- They validate complex resource dependencies before Azure API interaction
- They provide clear error messages to users before resource `creation`/`update`

**Testing Best Practices:**
- **Error Scenarios**: Test all invalid field combinations that should trigger validation errors
- **Success Scenarios**: Usually covered by other test cases (e.g., `basic`, `update`, and `complete`)
- **Edge Cases**: Test boundary conditions and corner cases
- **Error Message Validation**: Verify specific error messages using `ExpectError: regexp.MustCompile()`
- **Field Path Accuracy**: Ensure error messages include correct field paths and constraints
- **Azure API Alignment**: Test that validations match actual Azure API behavior

### CustomizeDiff Testing Best Practices

**Property Validation Boundary:**
- Do not add acceptance tests purely to prove simple property validation when that validator is already covered by a unit test.
- Reserve acceptance validation tests for cases where provider behavior needs to be proven beyond unit-test coverage, such as broader lifecycle behavior, Azure-specific cross-field constraints, or runtime interactions that unit tests do not exercise.

### Provider Feature-Flagged CRUD Branch Coverage

When a provider-level `features` setting changes create, update, delete, import, overwrite, or destroy semantics, the default lifecycle matrix may leave the non-default branch unproven even when `basic`, `requiresImport`, `complete`, `update`, and import coverage are already present.

A practical high-signal pattern is:

- apply prerequisite infrastructure first
- use `CheckWithClientForResource`, `CheckWithClientWithoutResource`, or `CheckWithClient`, as appropriate, to create or modify the pre-existing remote object outside Terraform
- apply the feature-enabled configuration that exercises the non-default branch
- verify overwrite, adoption, or the equivalent changed-branch behavior with one focused proof point, such as a changed field that would fail without the feature-enabled path

**Generalized Pattern:**
```go
func TestAcc{{RESOURCE_NAME}}_featureFlaggedBranch(t *testing.T) {
    data := acceptance.BuildTestData(t, "azurerm_{{RESOURCE_SLUG}}", "test")
    r := {{RESOURCE_HELPER}}{}

    data.ResourceTest(t, r, []acceptance.TestStep{
        {
            Config: r.prerequisites(data),
            Check: acceptance.ComposeTestCheckFunc(
                data.CheckWithClientForResource(r.createOutsideTerraform(data), "azurerm_{{PREREQUISITE_RESOURCE_TYPE}}.test"),
            ),
        },
        {
            Config: r.featureEnabled(data),
            Check: acceptance.ComposeTestCheckFunc(
                check.That(data.ResourceName).ExistsInAzure(r),
                check.That(data.ResourceName).Key("{{FIELD_NAME}}").HasValue("{{EXPECTED_VALUE}}"),
            ),
        },
        data.ImportStep(),
    })
}
```

The callback passed to these helpers should keep the upstream acceptance harness `ClientCheckFunc` shape from `internal/acceptance/steps.go`:

```go
func (r {{RESOURCE_HELPER}}) createOutsideTerraform(data acceptance.TestData) func(ctx context.Context, clients *clients.Client, state *pluginsdk.InstanceState) error {
    return func(ctx context.Context, clients *clients.Client, state *pluginsdk.InstanceState) error {
        // Read the prerequisite resource ID or attributes from state when setup depends on a
        // related Terraform-managed object.
        // Use the service-local client from clients.*.
        // Create or mutate the remote object that should already exist before the next Terraform step.
        // Return an error if that setup fails.
        return nil
    }
}
```

**Resource-Scoped Variant:**
```go
{
    Config: r.prerequisites(data),
    Check: acceptance.ComposeTestCheckFunc(
        data.CheckWithClientForResource(r.prepareRelatedResource(data), "azurerm_{{RELATED_RESOURCE_TYPE}}.source"),
        data.CheckWithClientForResource(r.mutateRelatedResource(data), "azurerm_{{RELATED_RESOURCE_TYPE}}.source"),
    ),
},
```

That resource-scoped form is the pattern to use when the pre-existing remote setup or mutation needs the state of a related Terraform-managed object instead of `data.ResourceName`.

Use the helper variants this way:

- use `CheckWithClientForResource(...)` when setup depends on a related Terraform-managed prerequisite resource
- use `CheckWithClientWithoutResource(...)` when no Terraform state object is needed for the outside-Terraform setup
- use `CheckWithClient(...)` when the main resource is already in state and you are mutating a related remote object, not when proving a create-time pre-existing-remote-object branch

When one of these callback helpers needs to call an Azure polling helper such as `CreateOrUpdateThenPoll(...)`, `CreateOrReplaceThenPoll(...)`, `UpdateThenPoll(...)`, or `DeleteThenPoll(...)`, do not pass the provided callback `ctx` directly into the poller. First wrap it with `context.WithTimeout(...)` or `context.WithDeadline(...)`.

This is a repo-specific acceptance-test pattern rather than generic Go advice: in target-provider `internal/acceptance/steps.go`, these callback helpers pass `client.StopContext`, which is not guaranteed to carry a deadline, while Azure polling helpers require one.

Concrete fixed examples of this pattern came from Durable Task acceptance tests in `durable_task_scheduler_resource_test.go`, `durable_task_hub_resource_test.go`, and `durable_task_retention_policy_resource_test.go`.

**Bad Poller Pattern:**
```go
data.CheckWithClientForResource(func(ctx context.Context, clients *clients.Client, state *terraform.InstanceState) error {
    return clients.SomeService.SomeClient.CreateOrUpdateThenPoll(ctx, id, payload)
}, "azurerm_resource.test")
```

**Deadline-Wrapped Poller Pattern:**
```go
data.CheckWithClientForResource(func(ctx context.Context, clients *clients.Client, state *terraform.InstanceState) error {
    ctx, cancel := context.WithTimeout(ctx, 30*time.Minute)
    defer cancel()

    return clients.SomeService.SomeClient.CreateOrUpdateThenPoll(ctx, id, payload)
}, "azurerm_resource.test")
```

Use a timeout appropriate for the operation, commonly 15 to 60 minutes for Azure LRO-style acceptance-test setup or mutation.

**Troubleshooting Signal:**

If a test fails with `the context used must have a deadline attached for polling purposes`, first inspect callback-based acceptance setup using:

- `CheckWithClientForResource(...)`
- `CheckWithClientWithoutResource(...)`
- `CheckWithClient(...)`

and any callback that then calls an Azure poller such as:

- `CreateOrUpdateThenPoll(...)`
- `CreateOrReplaceThenPoll(...)`
- `UpdateThenPoll(...)`
- `DeleteThenPoll(...)`

In that failure mode, the usual fix is in the test callback itself: wrap the callback context with `context.WithTimeout(...)` or `context.WithDeadline(...)` before calling the poller.

Quota-sensitive acceptance execution is a separate problem from callback-context deadlines:

- for services with hard subscription quotas or low service limits, prefer sequential acceptance execution patterns such as `ResourceSequentialTest(...)`, `DataSourceTestInSequence(...)`, or runner-level `-parallel=1`
- do not misclassify quota failures as missing-deadline failures in callback-based poller setup

These examples are generalized from upstream provider patterns, but the durable part is the harness shape: `data.CheckWithClientForResource(...)`, `data.CheckWithClientWithoutResource(...)`, `data.CheckWithClient(...)`, and the `func(ctx context.Context, clients *clients.Client, state *pluginsdk.InstanceState) error` callback signature.

Prefer this direct Azure setup pattern over creating two Terraform-managed resources that intentionally target the same remote ID. Keep the scenario narrow and usually prove the shared branch behavior with one focused test unless sibling resources differ materially.

**Comprehensive Test Coverage:**
```go
func TestAccServiceName_customizeDiffValidation(t *testing.T) {
    data := acceptance.BuildTestData(t, "azurerm_service_name", "test")
    r := ServiceNameResource{}

    data.ResourceTest(t, r, []acceptance.TestStep{
        // Test invalid configuration
        {
            Config:      r.invalidConfiguration(data),
            ExpectError: regexp.MustCompile("`configuration` is required when `enabled` is `true`"),
        },
    })
}
```

**Azure-Specific Validation Testing:**
- Test Azure service-specific constraints (SKU dependencies, region limitations, etc.)
- Validate Azure API field combination requirements
- Test Azure resource lifecycle constraints
- Verify Azure service version-specific validations

### CustomizeDiff Testing Patterns

**For complete CustomizeDiff implementation patterns, import requirements, and detailed examples, see:** [Implementation Guide - CustomizeDiff Import Requirements](./implementation-guide.instructions.md#customizediff-import-requirements)

**Testing Azure-Specific CustomizeDiff Validation:**

**Essential Test Coverage:**
- **Error scenarios**: Test invalid field combinations with `ExpectError: regexp.MustCompile()`
- **Success scenarios**: Not required, they will be tested in the other test cases (e.g., `basic`, `update`, and `complete`)
- **Edge cases**: Test boundary conditions and Azure service constraints

**Key Testing Requirements:**
- Test Azure service-specific constraints (SKU dependencies, region limitations, etc.)
- Validate Azure API field combination requirements
- Test Azure resource lifecycle constraints
- Verify Azure service version-specific validations

**Advanced Testing Patterns:**
- Use `ResourceTestIgnoreRecreate` for CustomizeDiff ForceNew validation
- Test plan verification with ConfigPlanChecks for complex state transitions
- Validate error messages with specific regexp patterns

**For Azure-specific CustomizeDiff behaviors and validation patterns, see:** [Azure Patterns - CustomizeDiff Validation](./azure-patterns.instructions.md#customizediff-validation)

---

## Acceptance Testing Patterns

### Basic Resource Test
```go
func TestAcc{{RESOURCE_NAME}}_basic(t *testing.T) {
    data := acceptance.BuildTestData(t, "azurerm_{{RESOURCE_SLUG}}", "test")
    r := {{RESOURCE_HELPER}}{}

    data.ResourceTest(t, r, []acceptance.TestStep{
        {
            Config: r.basic(data),
            Check: acceptance.ComposeTestCheckFunc(
                check.That(data.ResourceName).ExistsInAzure(r),
            ),
        },
        data.ImportStep(), // Exclude sensitive fields only when the resource needs it
    })
}
```

### Resource Update Test
```go
func TestAcc{{RESOURCE_NAME}}_update(t *testing.T) {
    data := acceptance.BuildTestData(t, "azurerm_{{RESOURCE_SLUG}}", "test")
    r := {{RESOURCE_HELPER}}{}

    data.ResourceTest(t, r, []acceptance.TestStep{
        {
            Config: r.basic(data),
            Check: acceptance.ComposeTestCheckFunc(
                check.That(data.ResourceName).ExistsInAzure(r),
            ),
        },
        data.ImportStep(),
        {
            Config: r.updated(data),
            Check: acceptance.ComposeTestCheckFunc(
                check.That(data.ResourceName).ExistsInAzure(r),
            ),
        },
        data.ImportStep(),
    })
}
```

### Resource Requires Import Test
```go
func TestAcc{{RESOURCE_NAME}}_requiresImport(t *testing.T) {
    data := acceptance.BuildTestData(t, "azurerm_{{RESOURCE_SLUG}}", "test")
    r := {{RESOURCE_HELPER}}{}
	data.ResourceTest(t, r, []acceptance.TestStep{
		{
			Config: r.basic(data),
			Check: acceptance.ComposeTestCheckFunc(
				check.That(data.ResourceName).ExistsInAzure(r),
			),
		},
		data.RequiresImportErrorStep(r.requiresImport),
	})
}
```
---

<a id="📊-data-source-testing-patterns"></a>

## 📊 Data Source Testing Patterns

Data sources have different testing requirements than resources since they retrieve existing information rather than manage resource lifecycle.

When a data source test needs managed resources as setup and the associated resource exposes a `complete(data)` helper, prefer that helper as the default setup shape.
This gives the test a stable baseline for computed-field coverage, which data sources commonly assert.
Use `basic(data)` or another scenario-specific helper instead when no `complete(data)` helper exists, when the test is intentionally narrow, or when `complete(data)` would add unrelated setup noise.

**Basic Data Source Test:**
```go
func TestAcc{{DATA_SOURCE_NAME}}_basic(t *testing.T) {
    data := acceptance.BuildTestData(t, "azurerm_{{RESOURCE_SLUG}}", "test")
    r := {{DATA_SOURCE_HELPER}}{}

    data.DataSourceTest(t, []acceptance.TestStep{
        {
            Config: r.basic(data),
            Check: acceptance.ComposeTestCheckFunc(
                // Data sources don't have ExistsInAzure checks - they retrieve existing resources
                check.That(data.ResourceName).Key("name").HasValue(fmt.Sprintf("acctest-%d", data.RandomInteger)),
                check.That(data.ResourceName).Key("resource_group_name").HasValue(fmt.Sprintf("acctestRG-%d", data.RandomInteger)),
                check.That(data.ResourceName).Key("{{FIELD_NAME}}").HasValue("{{EXPECTED_VALUE}}"),
                check.That(data.ResourceName).Key("id").Exists(),
            ),
        },
    })
}
```

**Data Source Test Configuration Pattern:**
```go
func ({{DATA_SOURCE_HELPER}}) basic(data acceptance.TestData) string {
    return fmt.Sprintf(`
%s

data "azurerm_{{RESOURCE_SLUG}}" "test" {
    name                = azurerm_{{RESOURCE_SLUG}}.test.name
    resource_group_name = azurerm_{{RESOURCE_SLUG}}.test.resource_group_name
}
`, {{RESOURCE_HELPER}}{}.complete(data))
}
```

If the associated resource does not expose `complete(data)`, or the data source test is intentionally narrow, reuse `{{RESOURCE_HELPER}}{}.basic(data)` or another scenario-specific helper instead.

**Data Source Key Validation Guidelines:**
- **Field Verification**: Data sources should validate that expected fields are populated with correct values
- **Computed Field Verification**: Test that computed fields (like IDs, endpoints) are populated
- **Complex Structure Validation**: Use Key validation for nested data structures retrieved from Azure
- **No ImportStep**: Data sources don't support import, so all validation should be explicit

**Valid Data Source Key Validation Examples:**
```go
// VALID: Verifying data source retrieves correct values
check.That(data.ResourceName).Key("location").HasValue(data.Locations.Primary),
check.That(data.ResourceName).Key("tags.Environment").HasValue("Production"),

// VALID: Validating computed fields are populated
check.That(data.ResourceName).Key("id").Exists(),
check.That(data.ResourceName).Key("endpoint").Exists(),

// VALID: Complex structure validation for data sources
check.That(data.ResourceName).Key("log_scrubbing_rule.#").HasValue("2"),
check.That(data.ResourceName).Key("log_scrubbing_rule.0.match_variable").HasValue("QueryStringArgNames"),
```
---

<a id="🏗️-test-organization-and-structure"></a>

## 🏗️ Test Organization and Structure

### Acceptance Test File Structure
- **Test function placement**: Test functions should be placed before the `Exists` function in the test file
- **Helper function placement**: Test configuration helper functions should be placed after the `Exists` function
- **No duplicate functions**: Remove any duplicate or old test functions to maintain clean file structure
- **Consistent ordering**: Place tests in logical order (basic, update, requires import, other scenarios)

### Test Case Consolidation Guidelines

**HashiCorp Standard - Essential Tests:**
- **Basic Test**: Core functionality with minimal configuration
- **Update Test**: Resource update scenarios
- **Complete Test**: Full supported configuration coverage
- **Import Validation**: Use `ImportStep()` to validate the configured state when import is supported
- **RequiresImport Test**: Import conflict detection for resources by default; only omit it when the resource pattern gives a concrete reason it is not applicable

**Avoid Excessive Test Cases:**
- Multiple basic tests with minor variations
- Separate tests for each individual field
- Redundant validation tests that don't add value
- Over-testing obvious functionality

### Cross-Implementation Consistency Requirements

When working with related Azure resources that have both Linux and Windows variants (like VMSS), ensure validation logic and behavior consistency:

**Validation Logic Consistency:**
- **Same validation rules**: Linux and Windows implementations should use consistent CustomizeDiff validation logic
- **Field requirements**: If Windows requires field X for scenario Y, Linux should have similar requirements
- **Error messages**: Use consistent error message patterns across related implementations
- **Default behavior**: Ensure both implementations handle defaults and omitted fields consistently

---

<a id="☁️-azure-specific-testing-guidelines"></a>

## ☁️ Azure-Specific Testing Guidelines

### Resource Existence Checks

The implementation of resource existence checks differs between typed and untyped approaches:

**Typed Resource Existence Check:**
```go
func (r ServiceNameResource) Exists(ctx context.Context, clients *clients.Client, state *pluginsdk.InstanceState) (*bool, error) {
    id, err := parse.ServiceNameID(state.ID)
    if err != nil {
        return nil, err
    }

    resp, err := clients.ServiceName.ResourceClient.Get(ctx, *id)
    if err != nil {
        return nil, fmt.Errorf("reading %s: %+v", *id, err)
    }

    return utils.Bool(resp.Model != nil), nil
}
```

**UnTyped Resource Existence Check:**
```go
func ({{RESOURCE_HELPER}}) Exists(ctx context.Context, clients *clients.Client, state *pluginsdk.InstanceState) (*bool, error) {
    id, err := parse.{{RESOURCE_ID_TYPE}}(state.ID)
    if err != nil {
        return nil, err
    }

    resp, err := clients.{{SERVICE_CLIENT_PATH}}.Get(ctx, *id)
    if err != nil {
        return nil, fmt.Errorf("reading {{RESOURCE_LABEL}} (%s): %+v", *id, err)
    }

    return utils.Bool(resp.Model != nil), nil
}
```

### Azure Test Cleanup Issues

**Problem:** Azure resources with protective features block test cleanup.

**Solution:** Use provider feature flags to force deletion:
```go
provider "azurerm" {
  features {
    virtual_machine_scale_set {
      force_delete = true
    }
    key_vault {
      purge_soft_delete_on_destroy = true
    }
  }
}
```

**When to Use:**
- VMSS with resiliency enabled
- Key Vault with soft delete
- SQL databases with backup protection
- Any resource blocking normal cleanup

---

## 📚 Related Specialized Guidance

Use the `acceptance-testing` skill for:

- acceptance-test execution workflow
- environment prerequisites and narrow rerun commands
- failure triage and cleanup-oriented troubleshooting

Other specialized references:

### **Advanced Testing Patterns**
- 🔧 **Troubleshooting**: [troubleshooting-decision-trees.instructions.md](./troubleshooting-decision-trees.instructions.md) - Debugging test failures, common issues
- ❌ **Error Patterns**: [error-patterns.instructions.md](./error-patterns.instructions.md) - Error handling in tests, debugging patterns

### **Test Infrastructure**
- ⚡ **Performance**: [performance-optimization.instructions.md](./performance-optimization.instructions.md) - Test performance, scalability testing
- 🔐 **Security**: [security-compliance.instructions.md](./security-compliance.instructions.md) - Security testing patterns, compliance validation

### **Test Evolution**
- 🔄 **Migration Guide**: [migration-guide.instructions.md](./migration-guide.instructions.md) - Test migration patterns, breaking change testing
- 🔄 **API Evolution**: [api-evolution-patterns.instructions.md](./api-evolution-patterns.instructions.md) - Testing API changes, version compatibility
---
