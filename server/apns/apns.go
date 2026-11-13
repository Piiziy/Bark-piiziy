package apns

import (
	"crypto/tls"
	"crypto/x509"
	"fmt"
	"net/http"
	"os"
	"runtime"
	"strings"
	"time"

	"github.com/mritd/logger"
	"github.com/sideshow/apns2"
	"github.com/sideshow/apns2/payload"
	"github.com/sideshow/apns2/token"
	"golang.org/x/net/http2"
)

type PushMessage struct {
	Id          string `form:"id,omitempty" json:"id,omitempty" xml:"id,omitempty" query:"id,omitempty"`
	DeviceToken string `form:"-" json:"-" xml:"-" query:"-"`
	DeviceType  string `form:"-" json:"-" xml:"-" query:"-"`
	DeviceKey   string `form:"device_key,omitempty" json:"device_key,omitempty" xml:"device_key,omitempty" query:"device_key,omitempty"`
	Subtitle    string `form:"subtitle,omitempty" json:"subtitle,omitempty" xml:"subtitle,omitempty" query:"subtitle,omitempty"`
	Title       string `form:"title,omitempty" json:"title,omitempty" xml:"title,omitempty" query:"title,omitempty"`
	Body        string `form:"body,omitempty" json:"body,omitempty" xml:"body,omitempty" query:"body,omitempty"`
	// ios notification sound(system sound please refer to http://iphonedevwiki.net/index.php/AudioServices)
	Sound     string                 `form:"sound,omitempty" json:"sound,omitempty" xml:"sound,omitempty" query:"sound,omitempty"`
	ExtParams map[string]interface{} `form:"ext_params,omitempty" json:"ext_params,omitempty" xml:"ext_params,omitempty" query:"ext_params,omitempty"`
}

// Check if it's an empty message, empty messages might be silent push notifications
func (p PushMessage) IsEmptyAlert() bool {
	return p.Title == "" && p.Body == "" && p.Subtitle == ""
}

func (p PushMessage) IsDelete() bool {
	val := p.ExtParams["delete"]
	return val == "1" || val == 1 || val == 1.0
}

const PayloadMaximum = 4096

// Config holds the APNs credentials. Nothing secret is compiled into the binary:
// every value comes from flags / environment variables (see main.go).
type Config struct {
	// PEM contents of the .p8 auth key. Takes precedence over KeyFile.
	Key string
	// Path to the .p8 auth key file.
	KeyFile string
	KeyID   string
	TeamID  string
	// Bundle ID of the iOS app, e.g. com.piiziy.homepush
	Topic string
	// Bundle ID of the watchOS app. Defaults to Topic + ".watch".
	WatchTopic string
	// Use the APNs sandbox (development builds installed from Xcode).
	// TestFlight / App Store builds use production.
	Sandbox bool
	// Size of the APNs client pool.
	MaxClients int
}

var (
	cfg     Config
	clients = make(chan *apns2.Client, 1)
)

// Configure validates cfg and (re)creates the APNs client pool.
func Configure(c Config) error {
	if c.Key == "" && c.KeyFile != "" {
		b, err := os.ReadFile(c.KeyFile)
		if err != nil {
			return fmt.Errorf("read APNs key file: %w", err)
		}
		c.Key = string(b)
	}
	var missing []string
	if strings.TrimSpace(c.Key) == "" {
		missing = append(missing, "BARK_APNS_KEY or BARK_APNS_KEY_FILE")
	}
	if c.KeyID == "" {
		missing = append(missing, "BARK_APNS_KEY_ID")
	}
	if c.TeamID == "" {
		missing = append(missing, "BARK_APNS_TEAM_ID")
	}
	if c.Topic == "" {
		missing = append(missing, "BARK_APNS_TOPIC")
	}
	if len(missing) > 0 {
		return fmt.Errorf("missing APNs configuration: %s", strings.Join(missing, ", "))
	}
	if c.WatchTopic == "" {
		c.WatchTopic = c.Topic + ".watch"
	}
	if c.MaxClients < 1 {
		c.MaxClients = 1
	}
	cfg = c
	return ReCreateAPNS(c.MaxClients)
}

func ReCreateAPNS(maxClientCount int) error {
	if maxClientCount < 1 {
		return fmt.Errorf("invalid number of clients")
	}

	authKey, err := token.AuthKeyFromBytes([]byte(cfg.Key))
	if err != nil {
		return fmt.Errorf("failed to create APNS auth key: %w", err)
	}

	var rootCAs *x509.CertPool
	if runtime.GOOS == "windows" {
		rootCAs = x509.NewCertPool()
	} else {
		rootCAs, err = x509.SystemCertPool()
		if err != nil {
			return fmt.Errorf("failed to get rootCAs: %w", err)
		}
	}

	for _, ca := range apnsCAs {
		rootCAs.AppendCertsFromPEM([]byte(ca))
	}

	host := apns2.HostProduction
	if cfg.Sandbox {
		host = apns2.HostDevelopment
	}

	newClients := make(chan *apns2.Client, maxClientCount)

	for i := 0; i < min(runtime.NumCPU(), maxClientCount); i++ {
		client := &apns2.Client{
			Token: &token.Token{
				AuthKey: authKey,
				KeyID:   cfg.KeyID,
				TeamID:  cfg.TeamID,
			},
			HTTPClient: &http.Client{
				Transport: &http2.Transport{
					DialTLS: apns2.DialTLS,
					TLSClientConfig: &tls.Config{
						RootCAs: rootCAs,
					},
				},
				Timeout: apns2.HTTPClientTimeout,
			},
			Host: host,
		}
		logger.Infof("create apns client: %d", i)
		newClients <- client
	}
	clients = newClients

	logger.Infof("init apns client success (topic=%s, host=%s)", cfg.Topic, host)
	return nil
}

func Push(msg *PushMessage) (code int, err error) {
	pl := payload.NewPayload().MutableContent()
	pushType := apns2.PushTypeAlert
	if msg.IsDelete() {
		// Silent push notification
		pl = pl.ContentAvailable()
		pushType = apns2.PushTypeBackground
	} else {
		// Regular push notification
		pl = pl.AlertTitle(msg.Title).
			AlertSubtitle(msg.Subtitle).
			AlertBody(msg.Body).
			Sound(msg.Sound).
			Category("myNotificationCategory")
		group, exist := msg.ExtParams["group"]
		if exist {
			pl = pl.ThreadID(group.(string))
		}
	}

	for k, v := range msg.ExtParams {
		// Change all parameter names to lowercase to prevent inconsistent capitalization
		pl.Custom(strings.ToLower(k), fmt.Sprintf("%v", v))
	}

	client := <-clients // grab a client from the pool
	clients <- client   // add the client back to the pool

	notificationTopic := cfg.Topic
	if msg.DeviceType == "watchos" {
		notificationTopic = cfg.WatchTopic
	}

	resp, err := client.Push(&apns2.Notification{
		CollapseID:  msg.Id,
		DeviceToken: msg.DeviceToken,
		Topic:       notificationTopic,
		Payload:     pl,
		Expiration:  time.Now().Add(24 * time.Hour),
		PushType:    pushType,
	})
	if err != nil {
		return 500, err
	}
	if resp.StatusCode != 200 {
		return resp.StatusCode, fmt.Errorf("%s", resp.Reason)
	}
	return 200, nil
}
