package groupicons

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestLookupAndFallback(t *testing.T) {
	dir := t.TempDir()
	p := filepath.Join(dir, "group-icons.json")
	os.WriteFile(p, []byte(`{"home":{"icon":"https://x/house.png"},"door":"https://x/door.png","*":"https://x/bell.png"}`), 0o644)
	s, err := Open(p)
	if err != nil {
		t.Fatal(err)
	}
	cases := map[string]string{"home": "https://x/house.png", "door": "https://x/door.png", "other": "https://x/bell.png", "": "https://x/bell.png"}
	for g, want := range cases {
		if e, ok := s.Lookup(g); !ok || e.Icon != want {
			t.Errorf("Lookup(%q) = %q,%v want %q", g, e.Icon, ok, want)
		}
	}
}

func TestMissingFileAndPersist(t *testing.T) {
	p := filepath.Join(t.TempDir(), "sub", "group-icons.json")
	s, err := Open(p)
	if err != nil {
		t.Fatal(err)
	}
	if _, ok := s.Lookup("home"); ok {
		t.Fatal("expected no entry")
	}
	if err := s.Set("home", Entry{Icon: "ftp://bad"}); err == nil {
		t.Fatal("expected validation error")
	}
	if err := s.Set("home", Entry{Icon: "https://x/house.png"}); err != nil {
		t.Fatal(err)
	}
	s2, _ := Open(p)
	if e, ok := s2.Lookup("home"); !ok || e.Icon != "https://x/house.png" {
		t.Fatalf("not persisted: %v %v", e, ok)
	}
	if err := s2.Delete("home"); err != nil {
		t.Fatal(err)
	}
	if _, ok := s2.Lookup("home"); ok {
		t.Fatal("expected deleted")
	}
}

func TestHotReload(t *testing.T) {
	p := filepath.Join(t.TempDir(), "g.json")
	os.WriteFile(p, []byte(`{"home":"https://x/a.png"}`), 0o644)
	s, _ := Open(p)
	os.WriteFile(p, []byte(`{"home":"https://x/bb.png"}`), 0o644)
	future := time.Now().Add(2 * time.Second)
	os.Chtimes(p, future, future)
	if e, _ := s.Lookup("home"); e.Icon != "https://x/bb.png" {
		t.Fatalf("not reloaded: %q", e.Icon)
	}
	// Broken file keeps last good table.
	os.WriteFile(p, []byte(`{broken`), 0o644)
	future = future.Add(2 * time.Second)
	os.Chtimes(p, future, future)
	if e, _ := s.Lookup("home"); e.Icon != "https://x/bb.png" {
		t.Fatalf("lost last good table: %q", e.Icon)
	}
}

func TestApply(t *testing.T) {
	s, _ := Open("")
	s.Set("home", Entry{Icon: "https://x/house.png"})
	p := map[string]interface{}{"group": "home"}
	s.Apply(p)
	if p["icon"] != "https://x/house.png" {
		t.Fatalf("icon not applied: %v", p)
	}
	p = map[string]interface{}{"group": "home", "icon": "https://x/mine.png"}
	s.Apply(p)
	if p["icon"] != "https://x/mine.png" {
		t.Fatalf("explicit icon overwritten: %v", p)
	}
	p = map[string]interface{}{"group": "other"}
	s.Apply(p)
	if _, ok := p["icon"]; ok {
		t.Fatalf("unexpected icon without fallback: %v", p)
	}
}
