# Sanitized Fixture: Committed Review Applies Singleton No-List Exception This fixture is synthetic and sanitized for regression benchmarking. ## Scenario A committed review sees a new child resource whose provider semantics model only one configuration object per parent. The resource uses a fixed child endpoint pattern, represented by a synthetic ID type and a fixed path suffix, while the underlying SDK package may still expose list methods that are not meaningful for the Terraform surface. The modeled failure mode is that review notices the SDK list method and raises a generic missing-list-resource issue. ## Simplified Change Shape ```text
Added:
- internal/services/example/parse.go
- internal/services/example/example_singleton_resource.go
- internal/services/example/registration.go Behavioral signal:
- resource ID path ends in a fixed child segment
- only one instance exists per parent
``` ## Expected Review Behavior A correct committed review should: - recognize the singleton-child implementation evidence
- avoid raising a plain missing-list-resource issue
- handle the omission through the documented exception-aware path instead ## Expected Must-Catch Outcomes - `singleton-list-exception-aware` ## Expected Must-Not-Flag Outcomes - `generic-missing-list-issue-for-singleton`# Sanitized Fixture: Committed Review Singleton No-List Exception This fixture is synthetic and sanitized for regression benchmarking. ## Scenario A committed review inspects a new singleton child configuration resource. The provider code models the resource as a fixed child endpoint under a parent resource, and the ID/parsing layer makes that singleton shape explicit. The SDK package also exposes a list method for the broader service surface, but that method does not imply a meaningful Terraform list resource for this singleton child object. ## Simplified Change Shape ```text
Added:
- internal/services/example/parse.go
- internal/services/example/registration.go
- internal/services/example/example_singleton_resource.go
- internal/services/example/example_singleton_resource_test.go Key implementation evidence:
- synthetic singleton child ID with a fixed trailing path segment
- CRUD built from the parent ID plus the singleton child path
- only one object can exist per parent
``` ## Expected Review Behavior A correct committed review should: - recognize the singleton-child implementation evidence
- avoid raising a plain missing-list-resource issue just because the SDK package has a list method
- if needed, mention the maintainer-reviewed no-list exception path instead of treating the omission as a normal blocker ## Expected Must-Catch Outcomes - `singleton-no-list-exception-awareness` ## Expected Must-Not-Flag Outcomes - `generic-missing-list-resource-issue`
