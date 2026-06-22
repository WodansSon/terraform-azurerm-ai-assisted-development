---
applyTo: "internal/**/*.go"
description: Code clarity and policy enforcement guidelines for Terraform AzureRM provider Go files. Includes detailed rules for comments, imports, implementation patterns, and quality standards.
---

# Code Clarity and Policy Enforcement Guidelines


This file is a companion guide. Implementation compliance rules are defined by the implementation compliance contract:

- `.github/instructions/implementation-compliance-contract.instructions.md` (see `Canonical sources of truth (precedence)`).

Use this guide for comment discipline, code-clarity heuristics, and worked implementation-quality patterns.
If this guide conflicts with the implementation contract, follow the contract and update this guide to re-align.

For authoritative code-clarity compliance, use the implementation contract as the source of truth for `IMPL-CODE-*` rules.
This guide stays focused on review heuristics, worked examples, and quick decision aids.


**Related Guidelines:**
- 🏗️ **Core Implementation**: [implementation-guide.instructions.md](./implementation-guide.instructions.md) - Main coding standards and patterns
- ☁️ **Azure Patterns**: [azure-patterns.instructions.md](./azure-patterns.instructions.md) - PATCH operations, CustomizeDiff validation, Azure-specific behaviors
- 🧪 **Testing Standards**: [testing-guidelines.instructions.md](./testing-guidelines.instructions.md) - Comprehensive test requirements and patterns


## Comment Discipline Heuristics

For the authoritative comment policy, see `IMPL-CODE-001` in `.github/instructions/implementation-compliance-contract.instructions.md`.

Code must be self-documenting. Comments are the exception, not the rule.

**Default posture:** write code without comments.

**Comments are usually only worth keeping in these cases:**
- Azure API-specific quirks not obvious from code
- Complex business logic that cannot be simplified
- Azure SDK workarounds for limitations/bugs
- Non-obvious state patterns (PATCH operations, residual state)

**Common comment red flags:**
- Variable assignments or struct initialization
- Standard Terraform/Go patterns
- Self-explanatory function calls
- Field mappings or obvious logic
- Error handling or nil checks

**Quick review check before keeping a comment:**
1. Can I refactor instead? -> **YES: Refactor, don't comment**
2. Is this an Azure API quirk? -> **MAYBE: Comment acceptable**
3. Is this self-explanatory? -> **YES: NO COMMENT**

**🔍 Useful review prompts:**
When a comment seems necessary, the reviewer should still be able to explain:
- Which of the 4 exception cases applies?
- Why code cannot be self-explanatory?
- What specific Azure behavior needs documentation?

**FINAL CHECK:** "Can I eliminate this comment through better code?"

### 🚫 Common Comment Red Flags

These are the first comment categories to challenge during review:
- Variable assignments, struct initialization, basic operations
- Standard Terraform patterns (CRUD operations, schema definitions)
- Self-explanatory function calls or routine Azure API calls
- Field mappings between Terraform and Azure API models
- Obvious conditional logic or loops
- Standard Go patterns (error handling, nil checks, etc.)

### Comment Review Process

If a comment remains, the author should be able to explain:
- Which exception case this comment falls under
- Why the code cannot be self-explanatory through better naming/structure
- What specific Azure API behavior requires documentation (if applicable)

**SUGGESTED ACTION**: When flagging unnecessary comments, suggest how to make code self-explanatory instead:
- Better variable naming
- Function extraction
- Structure reorganization
- Pattern clarification

### Comment Validation Questions

Before allowing any comment, ask:
1. "Is this code unclear without a comment?" -> Refactor the code instead
2. "Would a developer be confused by this logic?" -> Only then consider a comment
3. "Is this documenting an Azure API quirk?" -> Comment may be acceptable

---

<a id="🎯-strategic-decision-making-guidance"></a>

## 🎯 Strategic Decision-Making Guidance

**Implementation Context Awareness**: When making coding decisions during pair programming, always consider:

**1. Comment Policy Review Priority**
- Start by asking whether code structure, naming, or extraction can eliminate the need for a comment.
- Treat comments as a last resort for Azure quirks, complex business logic, SDK workarounds, or non-obvious state management patterns.

**2. Implementation Pattern Context**
- **Typed vs Untyped resources**: Apply same comment standards regardless of implementation approach
- **Azure service constraints**: Comments acceptable for Azure-specific behaviors that cannot be expressed through code structure
- **CustomizeDiff patterns**: Complex validation logic may require explanation of Azure API constraints

**3. Performance-Critical Decisions**
- **Code clarity over comments**: Always prefer refactoring to commenting
- **Cross-pattern consistency**: Ensure comment policies apply uniformly across resource variants (Linux/Windows VMSS, etc.)
- **Maintainability impact**: Favor self-documenting code patterns that reduce long-term maintenance burden

**4. Quality Gate Integration**
- **Pre-submission validation**: Comments should be explainable in review without relying on vague "for clarity" reasoning
- **Cross-file consistency**: Validate related implementations maintain identical comment policies
- **Azure API alignment**: Comments must reflect actual Azure service behavior, not implementation assumptions

---

## CustomizeDiff Import Requirements

**IMPORTANT**: CustomizeDiff implementation patterns depend on resource type and are comprehensively documented in the main implementation guide.

**For complete import patterns, examples, and decision criteria, see:** [Implementation Guide - CustomizeDiff Import Requirements](./implementation-guide.instructions.md#customizediff-import-requirements)

---

<a id="resource-implementation-standards"></a>

## Resource Implementation Standards

**CRUD Operations**: Ensure Create, Read, Update, Delete functions handle all edge cases

**Lifecycle Logging**: Do not add generic `Creating` / `Reading` / `Updating` / `Deleting` / `Import check` logs when they only repeat Terraform core or provider-native logging. Keep provider-side logging only when it adds unique diagnostic value, and prefer SDK/framework-level solutions if consistent lifecycle logging is wanted across resources.

**Schema Validation**: Verify all required fields, validation functions, and type definitions

**ForceNew Logic**: Check that properties requiring resource recreation are properly marked

**Timeouts**: Ensure appropriate timeout values for Azure operations (often long-running)

---

<a id="azure-api-integration-standards"></a>

## Azure API Integration Standards

**Error Handling**: Verify proper handling of Azure API errors, including 404s during Read operations

**Polling**: Check for proper implementation of long-running operation polling

**API Versions**: Ensure correct and consistent Azure API versions are used

**Authentication**: Verify proper use of Azure client authentication patterns

---

<a id="state-management-requirements"></a>

## State Management Requirements

**Drift Detection**: Ensure Read operations properly detect and handle resource drift

**Import Functionality**: Verify resource import works correctly and sets all required attributes

**Nested Resources**: Check proper handling of complex nested Azure resource structures

**Resource IDs**: Ensure consistent Azure resource ID parsing and formatting

---

<a id="testing-standards"></a>

## Testing Standards

**Acceptance Tests**: Verify comprehensive test coverage including error scenarios

**Test Cleanup**: Ensure tests properly clean up Azure resources

**Multiple Regions**: Check if tests account for regional Azure service availability

**Test Configuration**: Verify test fixtures use appropriate Azure resource configurations

---

<a id="documentation-quality"></a>

## Documentation Quality

**Examples**: Ensure realistic and working Terraform configuration examples

**Attributes**: Verify all resource attributes are documented with correct types

**Import Documentation**: Check that import syntax and requirements are clearly documented

---

<a id="enforcement-priority"></a>

## Review Focus Areas

1. **Highest**: Comment discipline and self-documenting code
2. **High**: Strategic decision-making during implementation work
3. **High**: CustomizeDiff import requirements and Azure API integration
4. **Medium**: Resource implementation and state-management quality
5. **Medium**: Testing and documentation completeness

**Performance Decision Framework**: Use strategic guidance above to make rapid, correct decisions during active development work.

---

<a id="⚡-quick-decision-trees"></a>

## ⚡ Quick Decision Trees

### **Comment Decision Tree (30-second evaluation)**
```text
Rule: evaluate in order and stop at the first matching condition.

Evaluate in order and stop at the first matching condition.

- If the code is not being written or reviewed -> Skip comment evaluation
- Else if the code documents a non-obvious Azure API quirk -> Comment MAY be acceptable
- Else if the code contains complex business logic -> Refactor first; comment only if the logic still cannot be made self-explanatory
- Else if the code documents an SDK workaround or limitation -> Comment MAY be acceptable
- Else -> Do not add a comment; refactor instead
```

### **Cross-Pattern Consistency Check (15-second scan)**
```text
Evaluate in order and stop at the first matching condition.

- If working on a resource with variants such as Linux/Windows VMSS -> Perform a quick consistency validation
- Else -> Use the standard implementation check

When quick consistency validation applies:
- Check sibling implementations for identical patterns
- Ensure validation logic matches
- Verify error messages use the same format
```

### **Azure API Integration Priority (10-second assessment)**
```text
Evaluate in order and stop at the first matching condition.

- If Azure API behavior is not involved -> Use standard coding patterns
- Else if the change involves a PATCH operation -> Check residual state handling
- Else if the change involves a long-running operation -> Verify polling implementation
- Else if the change involves Azure API error handling -> Ensure 404 detection patterns
- Else -> Apply high-priority Azure API validation
```

### **Implementation Approach Decision Tree (15-second assessment)**
```text
Evaluate in order and stop at the first matching condition.

- If the target is under `internal/provider/function/` -> Use the provider-defined function model
- Else if the target is an ephemeral resource or uses `EphemeralResources()` -> Use the ephemeral resource model
- Else if the target is a list resource or uses `sdk.FrameworkListWrappedResource` -> Use the framework list-resource model
- Else if this is a new ordinary resource or data source request -> Use the typed resource implementation model
- Else if this is maintenance of an existing untyped implementation -> Continue the current untyped implementation model
- Else if this is a major refactor of an existing untyped implementation -> Consider migration to the typed resource implementation model
- Else if this is a bug fix -> Maintain the existing implementation approach
- Else -> Match the model already used by the target file or workflow unless there is a clear migration reason
```

### **Pointer Package Decision Tree (5-second check)**
```text
Evaluate in order and stop at the first matching condition.

- If creating pointers -> Use pointer.To()
- Else if reading pointer values -> Use pointer.From() or pointer.FromType()
- Else if handling an SDK/API enum pointer field -> Use pointer.ToEnum[...] or pointer.FromEnum(...) only at the SDK boundary
- Else if handling a Terraform diff/schema value -> Do not use enum pointer helpers
- Else if defaults are needed -> Use pointer.FromTypeWithDefault()
- Else -> Replace manual pointer operations with pointer package functions
```

### **CustomizeDiff Validation Decision Tree (20-second evaluation)**
```text
Rule: evaluate in order and stop at the first matching condition.

- If the validation is for an Azure service constraint -> Use CustomizeDiff
- Else if the validation is simple field validation -> Use schema ValidateFunc
- Else if the validation is for a complex state transition -> Use programmatic ForceNew in CustomizeDiff
- Else -> Choose the lightest validation mechanism that still matches the real Azure constraint

When CustomizeDiff applies:
- If the constraint is a SKU dependency -> Add validation logic
- If the constraint is a region limitation -> Add a constraint check
- If the constraint is a field combination rule -> Add conditional validation
- If CustomizeDiff validation is added -> Add ExpectError coverage where appropriate
```

---

<a id="📊-performance-metrics--success-indicators"></a>

## 📊 Performance Metrics & Success Indicators

### **Real-Time Decision Quality Checklist**
- ✅ **Comment Decision**: Made in <30 seconds using decision tree
- ✅ **Cross-Pattern Check**: Sibling resource validated in <15 seconds
- ✅ **Azure Integration**: Priority assessment completed in <10 seconds
- ✅ **Quality Gate**: Pre-submission validation criteria met
- ✅ **Consistency**: Related implementations checked for alignment

### **Session Performance Indicators**
- **High Performance**: 90%+ decisions made using decision trees
- **Optimal Consistency**: Zero cross-pattern validation misses
- **Enforcement Success**: Zero unnecessary comments accepted
- **Strategic Focus**: Primary effort on code clarity over commenting

### **Continuous Improvement Signals**
- **Decision Speed**: Decreasing time to reach enforcement decisions
- **Pattern Recognition**: Faster identification of Azure API quirks vs standard patterns
- **Refactoring Suggestions**: Increasing ratio of refactoring suggestions vs comment acceptance

---

<a id="🎯-context-aware-ai-optimization"></a>

## 🎯 Context-Aware AI Optimization

### **Session Context Indicators**
- **Active Development**: User actively coding -> Apply real-time decision trees
- **Code Review**: User reviewing code -> Focus on consistency validation
- **Architecture Discussion**: User planning -> Emphasize strategic decision framework
- **Problem Solving**: User debugging -> Prioritize Azure API integration patterns

### **Smart Pattern Recognition**
- **Resource Type Context**: Automatically apply VMSS/Storage/Network specific patterns
- **Implementation Approach**: Detect typed vs untyped resource patterns for appropriate guidance
- **Azure Service Context**: Recognize CDN/Compute/Database specific enforcement needs
- **Development Phase**: Adjust guidance intensity based on implementation vs maintenance mode

### **Adaptive Enforcement Intensity**
- **High Intensity**: New resource implementation, complex Azure services, cross-pattern validation
- **Medium Intensity**: Bug fixes, updates, standard patterns
- **Low Intensity**: Documentation updates, minor configuration changes

---
