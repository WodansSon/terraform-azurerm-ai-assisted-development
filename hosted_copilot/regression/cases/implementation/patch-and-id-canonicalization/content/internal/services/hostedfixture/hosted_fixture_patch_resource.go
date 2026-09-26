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
	if !configured {
		return nil
	}

	enabled := true
	return &Feature{Enabled: &enabled}
}

func flattenResourceID(apiID string, parser ResourceIDParser) (string, error) {
	if _, err := parser.Parse(apiID); err != nil {
		return "", err
	}

	return apiID, nil
}
