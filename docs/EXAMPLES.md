<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../.github/examplesTitle-dark.png">
  <source media="(prefers-color-scheme: light)" srcset="../.github/examplesTitle-light.png">
  <img src="../.github/examplesTitle-light.png" alt="AI-Assisted Development Examples" width="900" height="80">
</picture>

> **Real-world examples and practical use cases for AI-powered Terraform development**

##
This guide provides real-world examples of using the Terraform AzureRM AI-Assisted Development toolkit.

## Table of Contents

- [Getting Started](#getting-started)
- [Resource Development](#resource-development)
- [Testing](#testing)
- [Documentation](#documentation)
- [Code Review](#code-review)
- [Advanced Scenarios](#advanced-scenarios)

---

## Getting Started

### First-Time Setup

After installation, open your terraform-provider-azurerm workspace:

```bash
cd ~/terraform-provider-azurerm
code .
```

The AI instructions are automatically loaded and ready to use!

---

## Resource Development

### Creating a New Resource from Scratch

**Scenario**: You need to implement support for Azure CDN Front Door Profile

**Step 1**: Open Copilot Chat and describe what you need

```
You: Create a new resource for Azure CDN Front Door Profile.
     It should use the typed SDK implementation pattern.
```

**What Copilot Does**:
1. ✅ Creates the resource file in the correct directory
2. ✅ Implements all CRUD operations
3. ✅ Adds proper schema with validations
4. ✅ Includes error handling with formatted errors
5. ✅ Adds metadata for state tracking

**Step 2**: Review and refine

```
You: Add CustomizeDiff for the tags field
```

Copilot updates the resource with proper CustomizeDiff implementation.

---

### Converting an Untyped Resource to Typed

**Scenario**: You want to modernize an existing untyped resource

```
You: Convert the azurerm_redis_cache resource to use typed SDK
```

**What Copilot Does**:
1. ✅ Identifies all untyped SDK calls
2. ✅ Replaces with typed equivalents
3. ✅ Updates state management
4. ✅ Maintains backward compatibility
5. ✅ Preserves existing functionality

---

### Implementing Azure API Patterns

**Scenario**: Your resource needs PATCH operations

```
You: Implement PATCH update for azurerm_cdn_frontdoor_profile
     following Azure API patterns
```

**What Copilot Generates**:

```go
func resourceCdnFrontDoorProfileUpdate(d *pluginsdk.ResourceData, meta interface{}) error {
    client := meta.(*clients.Client).Cdn.FrontDoorProfilesClient
    ctx, cancel := timeouts.ForUpdate(meta.(*clients.Client).StopContext, d)
    defer cancel()

    id, err := parse.FrontDoorProfileID(d.Id())
    if err != nil {
        return err
    }

    // Get existing state for PATCH
    existing, err := client.Get(ctx, id.ResourceGroup, id.Name)
    if err != nil {
        return fmt.Errorf("retrieving %s: %+v", id, err)
    }

    // Build PATCH payload
    update := cdn.ProfileUpdateParameters{
        Tags: tags.Expand(d.Get("tags").(map[string]interface{})),
    }

    if d.HasChange("sku") {
        update.Sku = &cdn.Sku{
            Name: cdn.SkuName(d.Get("sku.0.name").(string)),
        }
    }

    // Apply PATCH
    if _, err := client.Update(ctx, id.ResourceGroup, id.Name, update); err != nil {
        return fmt.Errorf("updating %s: %+v", id, err)
    }

    return resourceCdnFrontDoorProfileRead(d, meta)
}
```

---

## Testing

### Generating Acceptance Tests

**Scenario**: You need comprehensive tests for your new resource

```
You: Generate acceptance tests for azurerm_cdn_frontdoor_profile
     including basic, complete, and update scenarios
```

**What Copilot Generates**:

```go
func TestAccCdnFrontDoorProfile_basic(t *testing.T) {
    data := acceptance.BuildTestData(t, "azurerm_cdn_frontdoor_profile", "test")
    r := CdnFrontDoorProfileResource{}

    data.ResourceTest(t, r, []acceptance.TestStep{
        {
            Config: r.basic(data),
            Check: acceptance.ComposeTestCheckFunc(
                check.That(data.ResourceName).ExistsInAzure(r),
            ),
        },
        data.ImportStep(),
    })
}

func TestAccCdnFrontDoorProfile_complete(t *testing.T) {
    // Complete test with all fields
}

func TestAccCdnFrontDoorProfile_update(t *testing.T) {
    // Update scenarios
}
```

---

### Running Tests with AI Assistance

```
You: My test is failing with "404 Not Found". Help me debug.
```

**Copilot Response**:
```
The 404 error suggests the resource isn't being created properly.

Common causes:
1. Check the resource ID parsing
2. Verify the API endpoint in the client
3. Ensure the location is valid
4. Check if the resource group exists

Let me check your Create function...
[Provides specific fix for your code]
```

---

## Documentation

### Generating Resource Documentation

**Scenario**: You need to create documentation following provider standards

```
You: Create documentation for azurerm_cdn_frontdoor_profile
```

**What Copilot Generates**:

````markdown
---
subcategory: "CDN"
layout: "azurerm"
page_title: "Azure Resource Manager: azurerm_cdn_frontdoor_profile"
description: |-
  Manages a CDN Front Door Profile.
---

# azurerm_cdn_frontdoor_profile

Manages a CDN Front Door Profile.

## Example Usage

```terraform
resource "azurerm_cdn_frontdoor_profile" "example" {
  name                = "example-profile"
  resource_group_name = azurerm_resource_group.example.name
  sku_name            = "Standard_AzureFrontDoor"

  tags = {
    environment = "Production"
  }
}
```

## Arguments Reference

The following arguments are supported:

* `name` - (Required) The name of the CDN Front Door Profile...
* `resource_group_name` - (Required) The name of the Resource Group...
* `sku_name` - (Required) Specifies the SKU for this CDN Front Door Profile...

## Attributes Reference

In addition to the Arguments listed above - the following Attributes are exported:

* `id` - The ID of the CDN Front Door Profile.
* `resource_guid` - The UUID of this CDN Front Door Profile.

## Timeouts

The `timeouts` block allows you to specify timeouts...
````

---

### Docs + Schema Audit

**Scenario**: You have a provider documentation page and want to confirm it meets AzureRM docs standards and matches the actual Terraform schema.

**Step 1**: Open the documentation file you want to audit in your editor (the prompt only runs against the currently-open file under `website/docs/**`).

Example resource doc:
- `website/docs/r/cdn_frontdoor_profile.html.markdown`

Example data source doc:
- `website/docs/d/cdn_frontdoor_profile.html.markdown`

**Step 2**: Run the audit prompt:

```
You: /docs-schema-audit
```

If the active editor is not a file under `website/docs/**`, the prompt will tell you to open the target docs page and re-run it.

**What Copilot Does**:
1. ✅ Determines whether the doc is a resource (`website/docs/r/**`) or data source (`website/docs/d/**`)
2. ✅ Locates the schema under `internal/**` (when possible) and snapshots required/optional/computed/ForceNew fields
3. ✅ Checks docs structure rules (required sections differ for resources vs data sources; Import/Timeouts handled correctly)
4. ✅ Enforces parity: argument/attribute coverage, ordering rules, schema shape (block vs inline), ForceNew wording (resources only)
5. ✅ Validates examples, note notation, and link locale hygiene
6. ✅ Produces patch-ready minimal fixes for any issues

---

## Code Review

### Reviewing Local Changes

Before committing, get AI feedback:

```
You: /code-review-local-changes
```

**Copilot Review**:
```
Reviewing your changes to internal/services/cdn/cdn_frontdoor_profile_resource.go

✅ GOOD:
  - Schema follows provider patterns
  - Error handling uses fmt.Errorf with %+v
  - Resource ID parsing is correct
  - Timeouts are properly configured

⚠️ SUGGESTIONS:
  - Line 45: Consider adding validation for sku_name
  - Line 78: PATCH operation could use existing state
  - Line 112: Add CustomizeDiff for computed fields

❌ ISSUES:
  - Line 156: Comment is unnecessary (Code Clarity Policy)
  - Line 203: Missing error wrapping in Update function
```

---

### Reviewing Committed Changes

Review your PR before pushing:

```
You: /code-review-committed-changes
```

Gets feedback on all commits in your current branch.

---

## Advanced Scenarios

### Complex CustomizeDiff Logic

```
You: Implement CustomizeDiff that validates subnet_id is in the same
     location as the parent resource
```

**What Copilot Generates**:

```go
CustomizeDiff: pluginsdk.CustomizeDiffShim(func(ctx context.Context, d *pluginsdk.ResourceDiff, v interface{}) error {
    if d.HasChange("subnet_id") {
        subnetId := d.Get("subnet_id").(string)
        location := d.Get("location").(string)

        parsed, err := parse.SubnetID(subnetId)
        if err != nil {
            return fmt.Errorf("parsing subnet_id: %+v", err)
        }

        // Get subnet location and validate
        client := v.(*clients.Client).Network.SubnetsClient
        subnet, err := client.Get(ctx, parsed.ResourceGroup, parsed.VirtualNetworkName, parsed.Name, "")
        if err != nil {
            return fmt.Errorf("retrieving Subnet: %+v", err)
        }

        if !strings.EqualFold(*subnet.Location, location) {
            return fmt.Errorf("subnet must be in the same location (%q) as the parent resource", location)
        }
    }
    return nil
}),
```

---

### Migration Patterns

```
You: Create a state migration for azurerm_cdn_frontdoor_profile
     from v0 to v1 to handle ID format change
```

Copilot generates proper state migration code with upgrade functions.

---

### Multi-File Changes

```
You: Add support for response header action in azurerm_cdn_frontdoor_rule.
     Update all related files including tests and documentation.
```

**What Copilot Does**:
1. ✅ Updates resource schema
2. ✅ Adds expand/flatten functions
3. ✅ Updates tests
4. ✅ Updates documentation
5. ✅ Maintains consistency across all files

---

## Tips for Best Results

### 1. Be Specific

❌ Bad: "Add validation"
✅ Good: "Add ValidateFunc to sku_name that only allows Standard_AzureFrontDoor and Premium_AzureFrontDoor"

### 2. Reference Provider Patterns

✅ "Use the same pattern as azurerm_cdn_profile for tags handling"

### 3. Request Reviews Frequently

Run `/code-review-local-changes` often to catch issues early.

### 4. Learn from Generated Code

Study what Copilot generates to learn provider patterns.

### 5. Iterate and Refine

Ask follow-up questions to refine the generated code.

---

## Next Steps

- Check out [Troubleshooting Guide](TROUBLESHOOTING.md) for common issues
- Review the [Installation Guide](../installer/README.md) for detailed setup options
- Join [Discussions](https://github.com/WodansSon/terraform-azurerm-ai-assisted-development/discussions) to share experiences

---

**Happy Coding! 🚀**
