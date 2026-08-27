package hostedfixture

type Feature struct {
	Enabled *bool
}

type CanonicalResourceID interface {
	ID() string
}

type ResourceIDParser interface {
	Parse(string) (CanonicalResourceID, error)
}

func expandFeature(configured bool) *Feature {
	enabled := configured
	return &Feature{Enabled: &enabled}
}

func flattenResourceID(apiID string, parser ResourceIDParser) (string, error) {
	resourceID, err := parser.Parse(apiID)
	if err != nil {
		return "", err
	}

	return resourceID.ID(), nil
}
