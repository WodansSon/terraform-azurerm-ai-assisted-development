package hostedfixture

import "fmt"

func configuration(name string) string {
	return fmt.Sprintf(`
resource "azurerm_hosted_fixture" "test" {
  name = %q
}
`, name)
}
