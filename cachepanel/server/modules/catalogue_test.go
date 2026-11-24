package modules

import "testing"

func TestEncodeKeepsRepoFormat(t *testing.T) {
	entries := []Entry{
		{Slug: "system", Title: "System", Description: "Boot and Nix.", Required: true},
		{Slug: "gaming", Title: "Gaming", Description: "Steam & Proton <3>."},
	}
	got, err := encode(entries)
	want := "[\n  {\n    \"slug\": \"system\",\n    \"title\": \"System\",\n    \"description\": \"Boot and Nix.\",\n    \"required\": true\n  },\n" +
		"  {\n    \"slug\": \"gaming\",\n    \"title\": \"Gaming\",\n    \"description\": \"Steam & Proton <3>.\",\n    \"required\": false\n  }\n]\n"
	if err != nil || got != want {
		t.Fatalf("encode =\n%s", got)
	}
	if entries[1].Path() != "nixlyos/modules/gaming.nix" {
		t.Fatalf("path = %s", entries[1].Path())
	}
	if optional := Optional(entries); len(optional) != 1 || optional[0] != "gaming" {
		t.Fatalf("optional = %v", optional)
	}
}
