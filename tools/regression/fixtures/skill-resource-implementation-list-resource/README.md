# Sanitized Fixture: Resource Implementation Requires List Resource

This fixture is derived from a real new-resource workflow clarification, but the final artifact is sanitized and does not retain live PR identity.

## Scenario

A maintainer or contributor is asking for help creating a brand-new typed resource under `internal/services/example/`.

The historical failure mode is that implementation guidance focused on the base resource CRUD path and did not require the corresponding list resource, even though the upstream contributor workflow now makes it mandatory for all new resources unless an exception label is used.

## Simplified Request Shape

```text
Create a new typed resource under internal/services/example/
```

## Expected Guidance

A correct resource-implementation response should:

- Load the implementation contract rather than relying on a generic new-resource template
- Require Resource Identity for the new resource
- Require a corresponding list resource for the new resource by default
- Mention the maintainer-reviewed exception path only when no list API exists
- Plan list-resource acceptance coverage rather than stopping at base resource lifecycle tests

## Expected Must-Catch Outcomes

- `mandatory-list-resource`

## Expected Must-Not-Flag Outcomes

- `list-resource-optional`
