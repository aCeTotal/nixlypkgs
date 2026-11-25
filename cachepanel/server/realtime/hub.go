package realtime

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"sync"
	"time"

	"github.com/coder/websocket"
)

const (
	sendBuffer   = 256
	pingInterval = 25 * time.Second
	writeTimeout = 10 * time.Second
)

// Event names a browser message.
type Event string

const (
	BuildProgress   Event = "build.progress"
	VersionChanged  Event = "version.changed"
	PackageChanged  Event = "package.changed"
	CommitChanged   Event = "commit.changed"
	WatcherChanged  Event = "watcher.changed"
	ProfileChanged  Event = "profile.changed"
	TrustChanged    Event = "trust.changed"
	SourceChanged   Event = "source.changed"
	UpdateChanged   Event = "update.changed"
	ModuleChanged   Event = "module.changed"
	RecipeChanged   Event = "recipe.changed"
	UpstreamChanged Event = "upstream.changed"
)

type frame struct {
	Type Event `json:"type"`
	Data any   `json:"data"`
}

type Hub struct {
	mu      sync.Mutex
	clients map[chan []byte]struct{}
}

func NewHub() *Hub {
	return &Hub{clients: map[chan []byte]struct{}{}}
}

// Publish drops clients that fall behind.
func (h *Hub) Publish(event Event, data any) {
	message, err := json.Marshal(frame{Type: event, Data: data})
	if err != nil {
		slog.Error("encode event", "event", event, "error", err)
		return
	}
	h.mu.Lock()
	defer h.mu.Unlock()
	for send := range h.clients {
		select {
		case send <- message:
		default:
			close(send)
			delete(h.clients, send)
		}
	}
}

func (h *Hub) ServeWS(w http.ResponseWriter, r *http.Request) {
	conn, err := websocket.Accept(w, r, nil)
	if err != nil {
		return
	}
	send := make(chan []byte, sendBuffer)
	h.register(send)
	defer h.unregister(send)

	ctx := conn.CloseRead(r.Context())
	ticker := time.NewTicker(pingInterval)
	defer ticker.Stop()
	for err == nil {
		err = pump(ctx, conn, send, ticker.C)
	}
}

var errSlowClient = errors.New("websocket client too slow")

func pump(ctx context.Context, conn *websocket.Conn, send <-chan []byte, tick <-chan time.Time) error {
	select {
	case <-ctx.Done():
		return ctx.Err()
	case message, open := <-send:
		if !open {
			_ = conn.Close(websocket.StatusTryAgainLater, "too slow")
			return errSlowClient
		}
		writeCtx, cancel := context.WithTimeout(ctx, writeTimeout)
		defer cancel()
		return conn.Write(writeCtx, websocket.MessageText, message)
	case <-tick:
		pingCtx, cancel := context.WithTimeout(ctx, writeTimeout)
		defer cancel()
		return conn.Ping(pingCtx)
	}
}

func (h *Hub) register(send chan []byte) {
	h.mu.Lock()
	h.clients[send] = struct{}{}
	h.mu.Unlock()
}

func (h *Hub) unregister(send chan []byte) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if _, ok := h.clients[send]; ok {
		delete(h.clients, send)
		close(send)
	}
}
