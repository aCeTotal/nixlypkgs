package client

import (
	"net/http"
	"net/netip"
	"strings"
)

// Address trusts forwarding headers from loopback.
func Address(r *http.Request) netip.Addr {
	peer := peerAddress(r)
	forwarded := r.Header.Get("X-Forwarded-For")
	if !peer.IsLoopback() || forwarded == "" {
		return peer
	}
	last := strings.TrimSpace(forwarded[strings.LastIndexByte(forwarded, ',')+1:])
	addr, err := netip.ParseAddr(last)
	if err != nil {
		return peer
	}
	return addr.Unmap()
}

func HTTPS(r *http.Request) bool {
	if r.TLS != nil {
		return true
	}
	return peerAddress(r).IsLoopback() && r.Header.Get("X-Forwarded-Proto") == "https"
}

func peerAddress(r *http.Request) netip.Addr {
	addrPort, err := netip.ParseAddrPort(r.RemoteAddr)
	if err != nil {
		return netip.Addr{}
	}
	return addrPort.Addr().Unmap()
}
