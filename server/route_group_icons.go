package main

import (
	"fmt"
	"net/url"
	"path/filepath"

	"github.com/finb/bark-server/v2/apns"
	"github.com/finb/bark-server/v2/groupicons"
	"github.com/gofiber/fiber/v2"
	"github.com/gofiber/fiber/v2/utils"
	"github.com/mritd/logger"
	"github.com/urfave/cli/v2"
)

var (
	groupIcons  *groupicons.Store
	authEnabled bool
)

func initGroupIcons(c *cli.Context) error {
	path := c.String("group-icons")
	if path == "" && !c.Bool("serverless") && c.String("dsn") == "" {
		path = filepath.Join(c.String("data"), "group-icons.json")
	}
	store, err := groupicons.Open(path)
	if err != nil {
		return fmt.Errorf("load group icons: %w", err)
	}
	groupIcons = store
	logger.Infof("group icons: %d entries (%s)", len(store.All()), path)
	return nil
}

// applyGroupIcon fills msg's "icon" from the group icon table when the
// request did not specify one. An explicit icon always wins.
func applyGroupIcon(msg *apns.PushMessage) {
	if groupIcons == nil || msg.IsDelete() {
		return
	}
	groupIcons.Apply(msg.ExtParams)
}

func init() {
	registerRoute("group_icons", func(router fiber.Router) {
		router.Get("/group-icons", func(c *fiber.Ctx) error {
			return c.JSON(data(groupIcons.All()))
		})
		router.Put("/group-icons/:group", func(c *fiber.Ctx) error {
			if err := requireAuthForWrite(); err != nil {
				return c.Status(403).JSON(failed(403, "%s", err.Error()))
			}
			group, err := groupParam(c)
			if err != nil {
				return c.Status(400).JSON(failed(400, "invalid group: %v", err))
			}
			var e groupicons.Entry
			if err := c.BodyParser(&e); err != nil {
				return c.Status(400).JSON(failed(400, "request bind failed: %v", err))
			}
			if err := groupIcons.Set(group, e); err != nil {
				return c.Status(400).JSON(failed(400, "%s", err.Error()))
			}
			return c.JSON(data(groupIcons.All()))
		})
		router.Delete("/group-icons/:group", func(c *fiber.Ctx) error {
			if err := requireAuthForWrite(); err != nil {
				return c.Status(403).JSON(failed(403, "%s", err.Error()))
			}
			group, err := groupParam(c)
			if err != nil {
				return c.Status(400).JSON(failed(400, "invalid group: %v", err))
			}
			if err := groupIcons.Delete(group); err != nil {
				return c.Status(500).JSON(failed(500, "%s", err.Error()))
			}
			return c.JSON(data(groupIcons.All()))
		})
	})
}

// groupParam returns the unescaped :group path parameter. Fiber reuses
// request buffers, so the value must be copied before it is stored.
func groupParam(c *fiber.Ctx) (string, error) {
	return url.PathUnescape(utils.CopyString(c.Params("group")))
}

// Editing the table over HTTP is only allowed when Basic Auth protects
// the server; otherwise edit the JSON file directly.
func requireAuthForWrite() error {
	if !authEnabled {
		return fmt.Errorf("enable basic auth (BARK_SERVER_BASIC_AUTH_USER/PASSWORD) to edit group icons over HTTP, or edit the JSON file")
	}
	return nil
}
