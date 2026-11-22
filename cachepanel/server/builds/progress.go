package builds

import (
	"encoding/json"
	"io"
	"regexp"
	"strings"
	"time"

	"cachepanel/logtail"
)

// Nix activity and result types.
const (
	actCopyPaths   = 103
	actBuilds      = 104
	actBuild       = 105
	actSubstitute  = 108
	resLogLine     = 101
	resSetPhase    = 104
	resProgress    = 105
	resPostLogLine = 107
	levelError     = 0
	levelInfo      = 3
	nixPrefix      = "@nix "
	errorKeep      = 4 << 10
)

var ansi = regexp.MustCompile(`\x1b\[[0-9;]*[A-Za-z]`)

var verbs = map[int]string{actBuild: "Bygger ", actSubstitute: "Henter "}

type Counter struct {
	Done     int64 `json:"done"`
	Expected int64 `json:"expected"`
	Running  int64 `json:"running"`
	Failed   int64 `json:"failed"`
}

// Progress is live build state.
type Progress struct {
	VersionID       int64     `json:"versionId"`
	Attr            string    `json:"attr"`
	Name            string    `json:"name"`
	Builds          Counter   `json:"builds"`
	Paths           Counter   `json:"paths"`
	Activity        string    `json:"activity"`
	Phase           string    `json:"phase"`
	Line            string    `json:"line"`
	StartedAt       time.Time `json:"startedAt"`
	ExpectedSeconds int       `json:"expectedSeconds"`
}

type message struct {
	Action string            `json:"action"`
	ID     int64             `json:"id"`
	Type   int               `json:"type"`
	Level  int               `json:"level"`
	Text   string            `json:"text"`
	Msg    string            `json:"msg"`
	Fields []json.RawMessage `json:"fields"`
}

// parser turns internal-json into progress.
type parser struct {
	log      io.Writer
	progress Progress
	kinds    map[int64]int
	labels   map[int64]string
	errors   *logtail.Buffer
}

func newParser(log io.Writer, progress Progress) *parser {
	return &parser{log: log, progress: progress, kinds: map[int64]int{}, labels: map[int64]string{}, errors: logtail.New(errorKeep)}
}

func (p *parser) feed(line string) {
	payload, structured := strings.CutPrefix(line, nixPrefix)
	var m message
	if !structured || json.Unmarshal([]byte(payload), &m) != nil {
		p.write(line)
		return
	}
	switch m.Action {
	case "start":
		p.start(m)
	case "stop":
		p.stop(m.ID)
	case "result":
		p.result(m)
	case "msg":
		p.message(m)
	}
}

func (p *parser) start(m message) {
	p.kinds[m.ID] = m.Type
	if m.Level <= levelInfo && m.Text != "" {
		p.write(m.Text)
	}
	verb, named := verbs[m.Type]
	if !named || len(m.Fields) == 0 {
		return
	}
	p.labels[m.ID] = verb + storeName(text(m.Fields[0]))
	p.progress.Activity = p.labels[m.ID]
}

func (p *parser) stop(id int64) {
	delete(p.kinds, id)
	if _, labelled := p.labels[id]; !labelled {
		return
	}
	delete(p.labels, id)
	p.progress.Activity = ""
	var newest int64
	for other, label := range p.labels {
		if other > newest {
			newest, p.progress.Activity = other, label
		}
	}
}

func (p *parser) result(m message) {
	switch m.Type {
	case resProgress:
		p.count(m)
	case resLogLine, resPostLogLine:
		if len(m.Fields) > 0 {
			p.progress.Line = text(m.Fields[0])
			p.write(p.progress.Line)
		}
	case resSetPhase:
		if len(m.Fields) > 0 {
			p.progress.Phase = text(m.Fields[0])
		}
	}
}

func (p *parser) count(m message) {
	if len(m.Fields) < 4 {
		return
	}
	counter := Counter{Done: number(m.Fields[0]), Expected: number(m.Fields[1]), Running: number(m.Fields[2]), Failed: number(m.Fields[3])}
	switch p.kinds[m.ID] {
	case actBuilds:
		p.progress.Builds = counter
	case actCopyPaths:
		p.progress.Paths = counter
	}
}

func (p *parser) message(m message) {
	if m.Level > levelInfo {
		return
	}
	p.write(m.Msg)
	if m.Level == levelError {
		_, _ = p.errors.Write([]byte(ansi.ReplaceAllString(m.Msg, "") + "\n"))
	}
}

func (p *parser) write(line string) {
	_, _ = io.WriteString(p.log, ansi.ReplaceAllString(line, "")+"\n")
}

func text(raw json.RawMessage) string {
	var value string
	_ = json.Unmarshal(raw, &value)
	return value
}

func number(raw json.RawMessage) int64 {
	var value int64
	_ = json.Unmarshal(raw, &value)
	return value
}

// storeName strips store prefix and .drv.
func storeName(path string) string {
	base := path[strings.LastIndexByte(path, '/')+1:]
	if _, name, found := strings.Cut(base, "-"); found {
		base = name
	}
	return strings.TrimSuffix(base, ".drv")
}
