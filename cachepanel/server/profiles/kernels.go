package profiles

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"slices"

	"github.com/jackc/pgx/v5"

	"cachepanel/database"
	"cachepanel/rest"
)

// Newest commit with kernels.
const newestCatalogue = `SELECT kernels FROM commits WHERE kernels IS NOT NULL ORDER BY position DESC LIMIT 1`

var (
	errKernel    = rest.Unprocessable("invalid_kernel", "Unknown kernel")
	errSetting   = rest.Unprocessable("invalid_kernel_setting", "The kernel does not offer that setting")
	errCatalogue = rest.Conflict("no_kernel_catalogue", "The source has not offered any kernels yet")
)

// Offer is one catalogue kernel.
type Offer struct {
	Title       string             `json:"title"`
	Description string             `json:"description"`
	Settings    map[string]Setting `json:"settings"`
}

// Setting is one tunable value.
type Setting struct {
	Title       string   `json:"title"`
	Description string   `json:"description"`
	Kind        string   `json:"kind"`
	Options     []string `json:"options"`
	Default     string   `json:"default"`
}

func catalogue(ctx context.Context, db database.Querier) (map[string]Offer, error) {
	var offers map[string]Offer
	err := db.QueryRow(ctx, newestCatalogue).Scan(&offers)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, errCatalogue
	}
	return offers, err
}

// changed keeps non-default values.
func (o Offer) changed(settings map[string]string) (map[string]string, error) {
	kept := map[string]string{}
	for knob, value := range settings {
		setting, found := o.Settings[knob]
		if !found || !slices.Contains(setting.Options, value) {
			return nil, errSetting
		}
		if value != setting.Default {
			kept[knob] = value
		}
	}
	return kept, nil
}

// chooseKernel validates against the catalogue.
func chooseKernel(ctx context.Context, db database.Querier, profile Profile) (map[string]string, error) {
	offers, err := catalogue(ctx, db)
	if err != nil {
		return nil, err
	}
	offer, found := offers[profile.Kernel]
	if !found {
		return nil, errKernel
	}
	return offer.changed(profile.KernelSettings)
}

func (b *Rebuilder) kernels(w http.ResponseWriter, r *http.Request) error {
	var offers json.RawMessage
	err := b.DB.QueryRow(r.Context(), newestCatalogue).Scan(&offers)
	if errors.Is(err, pgx.ErrNoRows) {
		return rest.WriteJSON(w, http.StatusOK, map[string]Offer{})
	}
	if err != nil {
		return err
	}
	return rest.WriteRaw(w, offers)
}
