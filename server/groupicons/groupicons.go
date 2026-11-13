// Package groupicons maps a notification group (Bark's "group" parameter)
// to a default icon. When a push arrives without an explicit "icon",
// the server fills it in from this table, so every subscription/group
// (home, door, security, ...) gets its own picture automatically.
//
// The table is a JSON file, e.g.
//
//	{
//	  "home":     { "icon": "https://push.example.com/icons/house.png" },
//	  "security": "https://push.example.com/icons/rotating_light.png",
//	  "*":        { "icon": "https://push.example.com/icons/bell.png" }
//	}
//
// Values may be an object or a bare URL string. The "*" entry is the
// fallback used when the group has no entry (or no group was sent).
// The file is re-read automatically when it changes on disk.
package groupicons

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/url"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"
)

// Fallback is the key whose entry applies to groups without their own entry.
const Fallback = "*"

type Entry struct {
	Icon string `json:"icon"`
}

func (e *Entry) UnmarshalJSON(b []byte) error {
	var s string
	if err := json.Unmarshal(b, &s); err == nil {
		e.Icon = s
		return nil
	}
	type plain Entry
	var p plain
	if err := json.Unmarshal(b, &p); err != nil {
		return err
	}
	*e = Entry(p)
	return nil
}

// Validate checks that the icon is an absolute http(s) URL.
func (e Entry) Validate() error {
	u, err := url.Parse(e.Icon)
	if err != nil || (u.Scheme != "http" && u.Scheme != "https") || u.Host == "" {
		return fmt.Errorf("icon must be an absolute http(s) URL")
	}
	return nil
}

type Store struct {
	path    string
	mu      sync.RWMutex
	entries map[string]Entry
	modTime time.Time
	size    int64
}

// Open loads the table from path. A missing file is treated as an empty
// table (it is created on the first Set). An empty path gives an
// in-memory store that is never persisted.
func Open(path string) (*Store, error) {
	s := &Store{path: path, entries: map[string]Entry{}}
	if path == "" {
		return s, nil
	}
	if err := s.reload(true); err != nil {
		return nil, err
	}
	return s, nil
}

// reload re-reads the file if it changed. With force it always reads.
func (s *Store) reload(force bool) error {
	if s.path == "" {
		return nil
	}
	fi, err := os.Stat(s.path)
	if errors.Is(err, os.ErrNotExist) {
		s.mu.Lock()
		s.entries, s.modTime, s.size = map[string]Entry{}, time.Time{}, 0
		s.mu.Unlock()
		return nil
	}
	if err != nil {
		return err
	}
	s.mu.RLock()
	unchanged := fi.ModTime().Equal(s.modTime) && fi.Size() == s.size
	s.mu.RUnlock()
	if unchanged && !force {
		return nil
	}
	b, err := os.ReadFile(s.path)
	if err != nil {
		return err
	}
	entries := map[string]Entry{}
	if len(strings.TrimSpace(string(b))) > 0 {
		if err := json.Unmarshal(b, &entries); err != nil {
			return fmt.Errorf("parse %s: %w", s.path, err)
		}
	}
	s.mu.Lock()
	s.entries, s.modTime, s.size = entries, fi.ModTime(), fi.Size()
	s.mu.Unlock()
	return nil
}

// Lookup returns the entry for group, falling back to "*".
// If the file on disk is broken, the last good table keeps being used.
func (s *Store) Lookup(group string) (Entry, bool) {
	_ = s.reload(false)
	s.mu.RLock()
	defer s.mu.RUnlock()
	if e, ok := s.entries[group]; ok && e.Icon != "" {
		return e, true
	}
	if e, ok := s.entries[Fallback]; ok && e.Icon != "" {
		return e, true
	}
	return Entry{}, false
}

// All returns a copy of the table.
func (s *Store) All() map[string]Entry {
	_ = s.reload(false)
	s.mu.RLock()
	defer s.mu.RUnlock()
	out := make(map[string]Entry, len(s.entries))
	for k, v := range s.entries {
		out[k] = v
	}
	return out
}

func (s *Store) Set(group string, e Entry) error {
	if group == "" {
		return fmt.Errorf("group is empty")
	}
	if err := e.Validate(); err != nil {
		return err
	}
	return s.mutate(func(m map[string]Entry) { m[group] = e })
}

func (s *Store) Delete(group string) error {
	return s.mutate(func(m map[string]Entry) { delete(m, group) })
}

func (s *Store) mutate(f func(map[string]Entry)) error {
	_ = s.reload(false)
	s.mu.Lock()
	defer s.mu.Unlock()
	next := make(map[string]Entry, len(s.entries)+1)
	for k, v := range s.entries {
		next[k] = v
	}
	f(next)
	if s.path != "" {
		if err := writeAtomic(s.path, next); err != nil {
			return err
		}
		if fi, err := os.Stat(s.path); err == nil {
			s.modTime, s.size = fi.ModTime(), fi.Size()
		}
	}
	s.entries = next
	return nil
}

func writeAtomic(path string, m map[string]Entry) error {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	ordered := make(map[string]Entry, len(m))
	for _, k := range keys {
		ordered[k] = m[k]
	}
	b, err := json.MarshalIndent(ordered, "", "  ")
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	tmp, err := os.CreateTemp(filepath.Dir(path), ".group-icons-*.json")
	if err != nil {
		return err
	}
	defer os.Remove(tmp.Name())
	if _, err := tmp.Write(append(b, '\n')); err != nil {
		tmp.Close()
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	if err := os.Chmod(tmp.Name(), 0o644); err != nil {
		return err
	}
	return os.Rename(tmp.Name(), path)
}

// Apply sets params["icon"] from the table unless an icon is already
// present. params are the push's extra parameters (lower-cased keys).
func (s *Store) Apply(params map[string]interface{}) {
	if icon, ok := params["icon"]; ok && fmt.Sprint(icon) != "" {
		return
	}
	group, _ := params["group"].(string)
	if e, ok := s.Lookup(group); ok {
		params["icon"] = e.Icon
	}
}
