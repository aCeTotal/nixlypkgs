package versions

import (
	"encoding/json"

	"cachepanel/evaluate"
)

// columns feeds unnest() arrays.
type columns struct {
	attrs   []string
	errors  []string
	failed  int
	good    []string
	drvs    []string
	names   []string
	outputs [][]byte
}

func split(attrs []evaluate.Attr) (columns, error) {
	var cols columns
	for _, attr := range attrs {
		cols.attrs = append(cols.attrs, attr.Attr)
		cols.errors = append(cols.errors, attr.Error)
		if attr.Error != "" {
			cols.failed++
			continue
		}
		outputs, err := json.Marshal(attr.Outputs)
		if err != nil {
			return columns{}, err
		}
		cols.good = append(cols.good, attr.Attr)
		cols.drvs = append(cols.drvs, attr.DrvPath)
		cols.names = append(cols.names, attr.Name)
		cols.outputs = append(cols.outputs, outputs)
	}
	return cols, nil
}
