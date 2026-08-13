using System.Text.Json.Nodes;

namespace MonglePet.Settings;

internal sealed record AppSettingsMigrationResult(
    JsonObject Document,
    IReadOnlyList<string> Issues);

internal static class AppSettingsMigrator
{
    private const string CurrentPetDefaultMotion = "__monglepet_current_pet_default__";
    private const string DefaultBehavior = "__monglepet_default_behavior__";

    public static AppSettingsMigrationResult Migrate(
        JsonObject source,
        int sourceSchema,
        Func<Guid?, string, long?>? legacyMotionCycleMillisecondsResolver,
        Func<Guid>? settingsIdGenerator = null)
    {
        JsonObject document = source.DeepClone().AsObject();
        var issues = new List<string>();
        for (int schema = sourceSchema; schema < AppSettingsStore.CurrentSchemaVersion; schema++)
        {
            switch (schema)
            {
                case 1:
                    MigrateV1ToV2(document, legacyMotionCycleMillisecondsResolver, issues);
                    break;
                case 2:
                    MigrateV2ToV3(document);
                    break;
                case 3:
                    MigrateV3ToV4(document);
                    break;
                case 4:
                    MigrateV4ToV5(document);
                    break;
                case 5:
                    MigrateV5ToV6(document);
                    break;
                case 6:
                    MigrateV6ToV7(document);
                    break;
                case 7:
                    MigrateV7ToV8(document);
                    break;
                case 8:
                    MigrateV8ToV9(document);
                    break;
                case 9:
                    MigrateV9ToV10(document);
                    break;
                case 10:
                    MigrateV10ToV11(document, settingsIdGenerator ?? Guid.NewGuid);
                    break;
                default:
                    throw new InvalidOperationException($"Unsupported settings schema: {schema}.");
            }
        }

        return new AppSettingsMigrationResult(document, issues);
    }

    private static void MigrateV1ToV2(
        JsonObject document,
        Func<Guid?, string, long?>? cycleResolver,
        List<string> issues)
    {
        JsonArray sequences = RequiredArray(document, "sequences");
        JsonArray automaticRules = RequiredArray(document, "automaticRules");
        bool usesLegacyDefaults = UsesUnmodifiedLegacyDefaults(sequences, automaticRules);
        Guid? selectedId = TryReadGuid(document["selectedPetInstallationID"]);

        JsonArray migratedSequences;
        JsonNode? manualSequenceId;
        JsonArray migratedRules;
        if (usesLegacyDefaults)
        {
            migratedSequences = new JsonArray(CreateDefaultSequence());
            manualSequenceId = JsonValue.Create(DefaultBehavior);
            migratedRules = [];
        }
        else
        {
            migratedSequences = sequences.DeepClone().AsArray();
            foreach (JsonObject sequence in Objects(migratedSequences, "sequences"))
            {
                foreach (JsonObject step in Objects(RequiredArray(sequence, "steps"), "steps"))
                {
                    string motionId = RequiredString(step, "motionID");
                    long duration = RequiredLong(step, "durationMilliseconds");
                    long? cycle = cycleResolver?.Invoke(selectedId, motionId);
                    if (duration <= 0 || cycle is null or <= 0)
                    {
                        step["motionID"] = CurrentPetDefaultMotion;
                        step["repeatCount"] = 1;
                        issues.Add($"v1 모션 '{motionId}'을 기본 애니메이션 1회로 복구했습니다.");
                    }
                    else
                    {
                        int repeatCount = (int)Math.Clamp(
                            Math.Round(
                                (double)duration / cycle.Value,
                                MidpointRounding.AwayFromZero),
                            1,
                            100_000);
                        step["repeatCount"] = repeatCount;
                    }

                    step.Remove("durationMilliseconds");
                    step.Remove("playbackSpeed");
                }
            }

            manualSequenceId = document["manualSequenceID"]?.DeepClone();
            migratedRules = automaticRules.DeepClone().AsArray();
        }

        var petKey = new JsonObject { ["type"] = selectedId is null ? "builtIn" : "installed" };
        if (selectedId is Guid installationId)
        {
            petKey["installationID"] = installationId.ToString("D");
        }

        var profile = new JsonObject
        {
            ["petKey"] = petKey,
            ["mode"] = RequiredString(document, "behaviorMode"),
            ["manualSequenceID"] = manualSequenceId,
            ["sequences"] = migratedSequences,
            ["automaticRules"] = migratedRules,
        };
        document["behaviorProfiles"] = new JsonArray(profile);
        document.Remove("behaviorMode");
        document.Remove("manualSequenceID");
        document.Remove("sequences");
        document.Remove("automaticRules");
        document["schemaVersion"] = 2;
    }

    private static void MigrateV2ToV3(JsonObject document)
    {
        foreach (JsonObject profile in Profiles(document))
        {
            profile["movement"] = new JsonObject
            {
                ["mode"] = "fixed",
                ["speed"] = 160,
                ["cursorDistance"] = 96,
                ["stopRadius"] = 16,
                ["freeRoamingDwellMilliseconds"] = 6000,
                ["prefersFrontmostWindow"] = true,
                ["cursorFollowingMotionID"] = null,
                ["freeRoamingMotionID"] = null,
            };
            profile["pettingMotionID"] = null;
        }

        document["schemaVersion"] = 3;
    }

    private static void MigrateV3ToV4(JsonObject document)
    {
        JsonObject overlay = RequiredObject(document, "overlay");
        overlay["opacity"] = 1.0;
        overlay["pointerOverlapFadeEnabled"] = false;
        overlay["pointerOverlapOpacity"] = 0.2;
        overlay["pixelArtRendering"] = false;
        overlay["movementBoundary"] = new JsonObject
        {
            ["mode"] = "allDisplays",
            ["screenIdentifier"] = null,
            ["normalizedRect"] = null,
        };
        document["schemaVersion"] = 4;
    }

    private static void MigrateV4ToV5(JsonObject document)
    {
        JsonObject overlay = RequiredObject(document, "overlay");
        overlay["pixelArtRendering"] ??= false;
        foreach (JsonObject profile in Profiles(document))
        {
            JsonObject movement = RequiredObject(profile, "movement");
            JsonNode? cursorMotion = movement["cursorFollowingMotionID"]?.DeepClone();
            JsonNode? roamingMotion = movement["freeRoamingMotionID"]?.DeepClone();
            movement.Remove("cursorFollowingMotionID");
            movement.Remove("freeRoamingMotionID");
            movement["cursorFollowingAnimation"] = CreateAnimation(cursorMotion);
            movement["freeRoamingAnimation"] = CreateAnimation(roamingMotion);
        }

        document["schemaVersion"] = 5;
    }

    private static void MigrateV5ToV6(JsonObject document)
    {
        foreach (JsonObject profile in Profiles(document))
        {
            JsonObject movement = RequiredObject(profile, "movement");
            movement["cursorAvoidingIdleBehavior"] = "stationary";
            movement["cursorAvoidingDetectionDistance"] = 160;
            movement["cursorAvoidingSpeed"] = 320;
            movement["cursorAvoidingAnimation"] = CreateAnimation(null);
        }

        document["schemaVersion"] = 6;
    }

    private static void MigrateV6ToV7(JsonObject document)
    {
        foreach (JsonObject profile in Profiles(document))
        {
            profile["speech"] = new JsonObject
            {
                ["isEnabled"] = false,
                ["periodicIntervalMilliseconds"] = 60_000,
                ["phrases"] = new JsonArray(),
            };
        }

        document["schemaVersion"] = 7;
    }

    private static void MigrateV7ToV8(JsonObject document)
    {
        foreach (JsonObject profile in Profiles(document))
        {
            JsonObject speech = RequiredObject(profile, "speech");
            speech["theme"] = CreateDefaultTheme();
        }

        document["schemaVersion"] = 8;
    }

    private static void MigrateV8ToV9(JsonObject document)
    {
        foreach (JsonObject profile in Profiles(document))
        {
            JsonObject speech = RequiredObject(profile, "speech");
            JsonArray phrases = RequiredArray(speech, "phrases");
            speech["periodicIsEnabled"] = Objects(phrases, "phrases")
                .Any(phrase => string.Equals(
                    RequiredString(RequiredObject(phrase, "trigger"), "type"),
                    "periodic",
                    StringComparison.Ordinal));
            speech["periodicOrder"] = "random";
            speech["behaviorChangePolicy"] = "dismiss";
            foreach (JsonObject phrase in Objects(phrases, "phrases"))
            {
                phrase["displayMode"] = "timed";
            }
        }

        document["schemaVersion"] = 9;
    }

    private static void MigrateV9ToV10(JsonObject document)
    {
        foreach (JsonObject profile in Profiles(document))
        {
            JsonObject speech = RequiredObject(profile, "speech");
            speech["placement"] = new JsonObject
            {
                ["preferredPosition"] = "automatic",
                ["horizontalOffset"] = 0,
                ["gap"] = 8,
            };
        }

        document["schemaVersion"] = 10;
    }

    private static void MigrateV10ToV11(JsonObject document, Func<Guid> idGenerator)
    {
        var usedIds = new HashSet<Guid>();
        Guid NextId()
        {
            for (int attempt = 0; attempt < 100; attempt++)
            {
                Guid id = idGenerator();
                if (id != Guid.Empty && usedIds.Add(id))
                {
                    return id;
                }
            }
            throw new InvalidOperationException("A unique schema-v11 identifier could not be generated.");
        }

        // The fixture contract fixes this order: active instance first, then stored profiles.
        Guid instanceId = NextId();
        JsonArray profiles = RequiredArray(document, "behaviorProfiles");
        foreach (JsonObject profile in Objects(profiles, "behaviorProfiles"))
        {
            profile["profileID"] = NextId().ToString("D");
        }

        JsonObject petKey = CreateSelectedPetKey(document["selectedPetInstallationID"]);
        JsonObject? selectedProfile = Profiles(document).FirstOrDefault(profile =>
            PetKeysEqual(profile["petKey"], petKey));
        if (selectedProfile is null)
        {
            selectedProfile = DefaultAppSettingsDocument.CreateV10()["behaviorProfiles"]!
                .AsArray()[0]!.DeepClone().AsObject();
            selectedProfile["petKey"] = petKey.DeepClone();
            selectedProfile["profileID"] = NextId().ToString("D");
            profiles.Add(selectedProfile);
        }

        string profileId = RequiredString(selectedProfile, "profileID");
        JsonNode? presentation = document["lastUserPresentation"]?.DeepClone()
            ?? JsonValue.Create("awake");
        JsonNode? overlay = document["overlay"]?.DeepClone() ?? new JsonObject();
        document["activePetInstances"] = new JsonArray(new JsonObject
        {
            ["instanceID"] = instanceId.ToString("D"),
            ["behaviorProfileID"] = profileId,
            ["petKey"] = petKey,
            ["nickname"] = null,
            ["presentation"] = presentation,
            ["overlay"] = overlay,
            ["displayOrder"] = 0,
        });
        document["selectedPetInstanceID"] = instanceId.ToString("D");
        document.Remove("selectedPetInstallationID");
        document.Remove("lastUserPresentation");
        document.Remove("overlay");
        document["schemaVersion"] = 11;
    }

    private static JsonObject CreateSelectedPetKey(JsonNode? selectedInstallationId) =>
        TryReadGuid(selectedInstallationId) is Guid installationId
            ? new JsonObject
            {
                ["type"] = "installed",
                ["installationID"] = installationId.ToString("D"),
            }
            : new JsonObject { ["type"] = "builtIn" };

    private static bool PetKeysEqual(JsonNode? leftNode, JsonObject right)
    {
        if (leftNode is not JsonObject left ||
            !string.Equals(left["type"]?.GetValue<string>(), right["type"]?.GetValue<string>(), StringComparison.Ordinal))
        {
            return false;
        }
        if (string.Equals(right["type"]?.GetValue<string>(), "builtIn", StringComparison.Ordinal))
        {
            return true;
        }
        return TryReadGuid(left["installationID"]) == TryReadGuid(right["installationID"]);
    }

    private static JsonObject CreateDefaultSequence() => new()
    {
        ["id"] = DefaultBehavior,
        ["steps"] = new JsonArray(new JsonObject
        {
            ["motionID"] = CurrentPetDefaultMotion,
            ["repeatCount"] = 1,
        }),
        ["repeats"] = true,
    };

    private static JsonObject CreateAnimation(JsonNode? fallbackMotionId) => new()
    {
        ["fallbackMotionID"] = fallbackMotionId,
        ["usesDirectionalMotions"] = false,
        ["usesDiagonalMotions"] = false,
        ["directionMotionIDs"] = new JsonObject
        {
            ["left"] = null,
            ["right"] = null,
            ["up"] = null,
            ["down"] = null,
            ["upLeft"] = null,
            ["upRight"] = null,
            ["downLeft"] = null,
            ["downRight"] = null,
        },
    };

    private static JsonObject CreateDefaultTheme() => new()
    {
        ["colorStyle"] = "system",
        ["customBackgroundColor"] = new JsonObject
        {
            ["red"] = 1,
            ["green"] = 1,
            ["blue"] = 1,
        },
        ["customTextColor"] = new JsonObject
        {
            ["red"] = 0,
            ["green"] = 0,
            ["blue"] = 0,
        },
        ["backgroundOpacity"] = 0.96,
        ["fontSize"] = 14,
        ["contentPadding"] = 12,
        ["cornerRadius"] = 14,
        ["showsTail"] = false,
        ["tailAlignment"] = "center",
    };

    private static bool UsesUnmodifiedLegacyDefaults(
        JsonArray sequences,
        JsonArray rules)
    {
        string[] ids = ["idle", "focus", "rest", "sleep"];
        if (sequences.Count != ids.Length || rules.Count != 2)
        {
            return false;
        }

        for (int index = 0; index < ids.Length; index++)
        {
            if (sequences[index] is not JsonObject sequence)
            {
                return false;
            }

            JsonArray steps = RequiredArray(sequence, "steps");
            if (
                !string.Equals(RequiredString(sequence, "id"), ids[index], StringComparison.Ordinal) ||
                sequence["repeats"]?.GetValue<bool>() != true ||
                steps.Count != 1 ||
                steps[0] is not JsonObject step ||
                !string.Equals(RequiredString(step, "motionID"), ids[index], StringComparison.Ordinal) ||
                RequiredLong(step, "durationMilliseconds") != 3000)
            {
                return false;
            }
        }

        string[] ruleIds =
        [
            "30000000-0000-0000-0000-000000000001",
            "30000000-0000-0000-0000-000000000002",
        ];
        int[] priorities = [20, 10];
        long[] milliseconds = [600_000, 120_000];
        string[] sequenceIds = ["sleep", "rest"];
        for (int index = 0; index < rules.Count; index++)
        {
            if (rules[index] is not JsonObject rule ||
                !string.Equals(RequiredString(rule, "id"), ruleIds[index], StringComparison.Ordinal) ||
                rule["isEnabled"]?.GetValue<bool>() != true ||
                rule["priority"]?.GetValue<int>() != priorities[index] ||
                !string.Equals(
                    RequiredString(RequiredObject(rule, "condition"), "type"),
                    "idleAtLeast",
                    StringComparison.Ordinal) ||
                RequiredLong(RequiredObject(rule, "condition"), "milliseconds") != milliseconds[index] ||
                !string.Equals(
                    RequiredString(rule, "sequenceID"),
                    sequenceIds[index],
                    StringComparison.Ordinal))
            {
                return false;
            }
        }

        return true;
    }

    private static IEnumerable<JsonObject> Profiles(JsonObject document) =>
        Objects(RequiredArray(document, "behaviorProfiles"), "behaviorProfiles");

    private static IEnumerable<JsonObject> Objects(JsonArray array, string field)
    {
        foreach (JsonNode? node in array)
        {
            yield return node as JsonObject
                ?? throw new InvalidOperationException($"{field} must contain objects.");
        }
    }

    private static JsonObject RequiredObject(JsonObject parent, string field) =>
        parent[field] as JsonObject
        ?? throw new InvalidOperationException($"{field} must be an object.");

    private static JsonArray RequiredArray(JsonObject parent, string field) =>
        parent[field] as JsonArray
        ?? throw new InvalidOperationException($"{field} must be an array.");

    private static string RequiredString(JsonObject parent, string field) =>
        parent[field]?.GetValue<string>()
        ?? throw new InvalidOperationException($"{field} must be a string.");

    private static long RequiredLong(JsonObject parent, string field) =>
        parent[field]?.GetValue<long>()
        ?? throw new InvalidOperationException($"{field} must be an integer.");

    private static Guid? TryReadGuid(JsonNode? node) =>
        node is JsonValue value &&
        value.TryGetValue(out string? text) &&
        Guid.TryParse(text, out Guid id)
            ? id
            : null;
}
