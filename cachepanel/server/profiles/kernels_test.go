package profiles

import (
	"errors"
	"maps"
	"testing"
)

func TestOfferKeepsChangedSettings(t *testing.T) {
	offer := Offer{Settings: map[string]Setting{
		"tickRate":  {Options: []string{"300", "1000"}, Default: "1000"},
		"hugepages": {Options: []string{"always", "madvise"}, Default: "always"},
	}}
	kept, err := offer.changed(map[string]string{"tickRate": "1000", "hugepages": "madvise"})
	if err != nil || !maps.Equal(kept, map[string]string{"hugepages": "madvise"}) {
		t.Fatalf("changed = %v, %v", kept, err)
	}
	for _, bad := range []map[string]string{{"tickRate": "500"}, {"scheduler": "bore"}} {
		if _, err := offer.changed(bad); !errors.Is(err, errSetting) {
			t.Errorf("changed(%v) = %v", bad, err)
		}
	}
}
