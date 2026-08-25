using System.Text.Json.Nodes;

namespace MonglePet.Settings;

internal static class DefaultAppSettingsDocument
{
    public static JsonObject Create(Func<Guid>? settingsIdGenerator = null)
    {
        AppSettingsMigrationResult migration = AppSettingsMigrator.Migrate(
            CreateV10(),
            10,
            legacyMotionCycleMillisecondsResolver: null,
            settingsIdGenerator);
        AppSettings settings = AppSettingsDocumentMapper.FromDocument(
            migration.Document,
            settingsIdGenerator).Settings;
        settings = BuiltInBehaviorProfileDefaults.UpgradeLegacyNeutralProfiles(settings);
        return AppSettingsDocumentMapper.ToDocument(settings, migration.Document);
    }

    internal static JsonObject CreateV10() => JsonNode.Parse(
        """
        {
          "schemaVersion": 10,
          "selectedPetInstallationID": null,
          "lastUserPresentation": "awake",
          "overlay": {
            "screenIdentifier": null,
            "originX": 0,
            "originY": 0,
            "width": 192,
            "clickThrough": false,
            "opacity": 1.0,
            "pointerOverlapFadeEnabled": false,
            "pointerOverlapOpacity": 0.2,
            "pixelArtRendering": false,
            "movementBoundary": {
              "mode": "allDisplays",
              "screenIdentifier": null,
              "normalizedRect": null
            }
          },
          "behaviorProfiles": [
            {
              "petKey": { "type": "builtIn" },
              "mode": "automatic",
              "manualSequenceID": "__monglepet_default_behavior__",
              "sequences": [
                {
                  "id": "__monglepet_default_behavior__",
                  "steps": [
                    {
                      "motionID": "__monglepet_current_pet_default__",
                      "repeatCount": 1
                    }
                  ],
                  "repeats": true
                }
              ],
              "automaticRules": [],
              "pettingMotionID": null,
              "speech": {
                "isEnabled": false,
                "periodicIsEnabled": false,
                "periodicIntervalMilliseconds": 60000,
                "periodicOrder": "random",
                "behaviorChangePolicy": "dismiss",
                "phrases": [],
                "theme": {
                  "colorStyle": "system",
                  "customBackgroundColor": { "red": 1, "green": 1, "blue": 1 },
                  "customTextColor": { "red": 0, "green": 0, "blue": 0 },
                  "backgroundOpacity": 0.96,
                  "fontSize": 14,
                  "contentPadding": 12,
                  "cornerRadius": 14,
                  "showsTail": false,
                  "tailAlignment": "center"
                },
                "placement": {
                  "preferredPosition": "automatic",
                  "horizontalOffset": 0,
                  "gap": 8
                }
              },
              "movement": {
                "mode": "fixed",
                "speed": 160,
                "cursorDistance": 96,
                "stopRadius": 16,
                "freeRoamingDwellMilliseconds": 6000,
                "prefersFrontmostWindow": true,
                "cursorAvoidingIdleBehavior": "stationary",
                "cursorAvoidingDetectionDistance": 160,
                "cursorAvoidingSpeed": 320,
                "cursorFollowingAnimation": {
                  "fallbackMotionID": null,
                  "usesDirectionalMotions": false,
                  "usesDiagonalMotions": false,
                  "directionMotionIDs": {
                    "left": null, "right": null, "up": null, "down": null,
                    "upLeft": null, "upRight": null, "downLeft": null, "downRight": null
                  }
                },
                "freeRoamingAnimation": {
                  "fallbackMotionID": null,
                  "usesDirectionalMotions": false,
                  "usesDiagonalMotions": false,
                  "directionMotionIDs": {
                    "left": null, "right": null, "up": null, "down": null,
                    "upLeft": null, "upRight": null, "downLeft": null, "downRight": null
                  }
                },
                "cursorAvoidingAnimation": {
                  "fallbackMotionID": null,
                  "usesDirectionalMotions": false,
                  "usesDiagonalMotions": false,
                  "directionMotionIDs": {
                    "left": null, "right": null, "up": null, "down": null,
                    "upLeft": null, "upRight": null, "downLeft": null, "downRight": null
                  }
                }
              }
            }
          ]
        }
        """)!.AsObject();
}
