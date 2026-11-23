package auth

import (
	"crypto/rand"
	"crypto/subtle"
	"encoding/base64"
	"fmt"
	"strings"
	"unicode/utf8"

	"golang.org/x/crypto/argon2"

	"cachepanel/rest"
)

// OWASP argon2id parameters.
const (
	argonTime    = 3
	argonMemory  = 64 * 1024
	argonThreads = 2
	argonKeyLen  = 32
)

const (
	minPasswordLength = 8
	maxPasswordLength = 256
)

var encoding = base64.RawStdEncoding

func HashPassword(password string) string {
	salt := []byte(rand.Text())
	key := argon2.IDKey([]byte(password), salt, argonTime, argonMemory, argonThreads, argonKeyLen)
	return fmt.Sprintf("$argon2id$v=%d$m=%d,t=%d,p=%d$%s$%s",
		argon2.Version, argonMemory, argonTime, argonThreads, encoding.EncodeToString(salt), encoding.EncodeToString(key))
}

func verifyPassword(encoded, password string) bool {
	parts := strings.Split(encoded, "$")
	if len(parts) != 6 || parts[1] != "argon2id" {
		return false
	}
	var memory, time uint32
	var threads uint8
	if _, err := fmt.Sscanf(parts[3], "m=%d,t=%d,p=%d", &memory, &time, &threads); err != nil {
		return false
	}
	salt, saltErr := encoding.DecodeString(parts[4])
	want, keyErr := encoding.DecodeString(parts[5])
	if saltErr != nil || keyErr != nil || len(want) != argonKeyLen {
		return false
	}
	got := argon2.IDKey([]byte(password), salt, time, memory, threads, argonKeyLen)
	return subtle.ConstantTimeCompare(got, want) == 1
}

// Equalises timing for unknown users.
var decoyHash = HashPassword("decoy")

func validatePassword(password string) error {
	length := utf8.RuneCountInString(password)
	if length < minPasswordLength || length > maxPasswordLength {
		return rest.Unprocessable("invalid_password_length",
			fmt.Sprintf("The password needs %d to %d characters", minPasswordLength, maxPasswordLength))
	}
	return nil
}
