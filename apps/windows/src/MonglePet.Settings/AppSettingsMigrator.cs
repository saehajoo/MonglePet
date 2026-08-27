using System.Text;
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
        Func<Guid>? settingsIdGenerator = null,
        int? targetSchema = null)
    {
        int finalSchema = targetSchema ?? AppSettingsStore.CurrentSchemaVersion;
        if (finalSchema < sourceSchema || finalSchema > AppSettingsStore.CurrentSchemaVersion)
        {
            throw new ArgumentOutOfRangeException(nameof(targetSchema));
        }
        JsonObject document = source.DeepClone().AsObject();
        var issues = new List<string>();
        for (int schema = sourceSchema; schema < finalSchema; schema++)
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
                case 11:
                    MigrateV11ToV12(document);
                    break;
                case 12:
                    MigrateV12ToV13(document);
                    break;
                case 13:
                    MigrateV13ToV14(document);
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

    private static void MigrateV11ToV12(JsonObject document)
    {
        foreach (JsonObject profile in Profiles(document))
        {
            JsonArray sequences = RequiredArray(profile, "sequences");
            var usedIds = new HashSet<string>(StringComparer.Ordinal);
            var motionBehaviorIds = new Dictionary<string, string>(StringComparer.Ordinal);
            foreach (JsonObject sequence in Objects(sequences, "sequences"))
            {
                string id = RequiredString(sequence, "id");
                usedIds.Add(id);
                sequence["displayName"] = id == DefaultBehavior ? "기본" : id;
                if (IsSingleMotionBehavior(sequence, out string? motionId) && motionId is not null)
                {
                    motionBehaviorIds.TryAdd(motionId, id);
                }
            }

            string? PromoteMotion(JsonNode? node)
            {
                string? motionId = node?.GetValue<string?>()?.Trim();
                if (string.IsNullOrEmpty(motionId))
                {
                    return null;
                }
                if (motionBehaviorIds.TryGetValue(motionId, out string? existing))
                {
                    return existing;
                }
                string baseId = "__monglepet_motion_behavior__" + Base64Url(motionId);
                string id = baseId;
                for (int suffix = 2; !usedIds.Add(id); suffix++)
                {
                    id = $"{baseId}_{suffix}";
                }
                sequences.Add(new JsonObject
                {
                    ["id"] = id,
                    ["displayName"] = motionId,
                    ["steps"] = new JsonArray(new JsonObject
                    {
                        ["motionID"] = motionId,
                        ["repeatCount"] = 1,
                    }),
                    ["repeats"] = true,
                });
                motionBehaviorIds[motionId] = id;
                return id;
            }

            JsonObject movement = RequiredObject(profile, "movement");
            PromoteAnimation(movement, "cursorFollowingAnimation", "cursorFollowingBehavior", PromoteMotion);
            PromoteAnimation(movement, "freeRoamingAnimation", "freeRoamingBehavior", PromoteMotion);
            PromoteAnimation(movement, "cursorAvoidingAnimation", "cursorAvoidingBehavior", PromoteMotion);
            profile["pettingBehaviorID"] = PromoteMotion(profile["pettingMotionID"]);
            profile.Remove("pettingMotionID");

            JsonArray rules = RequiredArray(profile, "automaticRules");
            int idlePriority = HighestPriority(rules, "idleAtLeast");
            int applicationPriority = HighestPriority(rules, "application");
            var order = new JsonArray("movement");
            if (applicationPriority > idlePriority)
            {
                order.Add("application");
                order.Add("idle");
            }
            else
            {
                order.Add("idle");
                order.Add("application");
            }
            profile["automaticRulePriorityOrder"] = order;
        }
        document["schemaVersion"] = 12;
    }

    private static void MigrateV12ToV13(JsonObject document)
    {
        foreach (JsonObject profile in Profiles(document))
        {
            profile["randomSequenceIDs"] = new JsonArray();
            JsonObject movement = RequiredObject(profile, "movement");
            long dwell = ReadLongOr(movement["freeRoamingDwellMilliseconds"], 6_000);
            movement["randomizesFreeRoamingDwell"] = false;
            movement["freeRoamingDwellMinimumMilliseconds"] = Math.Max(500, dwell / 2);
        }
        document["schemaVersion"] = 13;
    }

    private static void MigrateV13ToV14(JsonObject document)
    {
        foreach (JsonObject profile in Profiles(document))
        {
            JsonObject movement = RequiredObject(profile, "movement");
            JsonNode? mode = movement["mode"]?.DeepClone() ?? JsonValue.Create("fixed");
            double speed = ReadDoubleOr(movement["speed"], 160);
            double cursorDistance = ReadDoubleOr(movement["cursorDistance"], 96);
            double stopRadius = ReadDoubleOr(movement["stopRadius"], 16);
            long dwell = ReadLongOr(movement["freeRoamingDwellMilliseconds"], 6_000);
            bool randomizesDwell = ReadBoolOr(movement["randomizesFreeRoamingDwell"], false);
            long minimumDwell = ReadLongOr(
                movement["freeRoamingDwellMinimumMilliseconds"],
                Math.Max(500, dwell / 2));
            bool prefersFrontmost = ReadBoolOr(movement["prefersFrontmostWindow"], true);

            JsonObject FreeRoaming(JsonNode? behavior) => new()
            {
                ["speed"] = speed,
                ["stopRadius"] = stopRadius,
                ["dwellMilliseconds"] = dwell,
                ["randomizesDwell"] = randomizesDwell,
                ["dwellMinimumMilliseconds"] = minimumDwell,
                ["prefersFrontmostWindow"] = prefersFrontmost,
                ["behavior"] = behavior?.DeepClone() ?? new JsonObject(),
            };

            profile["movement"] = new JsonObject
            {
                ["mode"] = mode,
                ["cursorFollowing"] = new JsonObject
                {
                    ["speed"] = speed,
                    ["cursorDistance"] = cursorDistance,
                    ["stopRadius"] = stopRadius,
                    ["behavior"] = movement["cursorFollowingBehavior"]?.DeepClone() ?? new JsonObject(),
                },
                ["freeRoaming"] = FreeRoaming(movement["freeRoamingBehavior"]),
                ["cursorAvoiding"] = new JsonObject
                {
                    ["idleBehavior"] = movement["cursorAvoidingIdleBehavior"]?.DeepClone() ?? JsonValue.Create("stationary"),
                    ["detectionDistance"] = movement["cursorAvoidingDetectionDistance"]?.DeepClone() ?? JsonValue.Create(160),
                    ["speed"] = movement["cursorAvoidingSpeed"]?.DeepClone() ?? JsonValue.Create(320),
                    ["stopRadius"] = stopRadius,
                    ["behavior"] = movement["cursorAvoidingBehavior"]?.DeepClone() ?? new JsonObject(),
                    ["idleFreeRoaming"] = FreeRoaming(movement["freeRoamingBehavior"]),
                },
            };
        }
        document["schemaVersion"] = 14;
    }

    private static void PromoteAnimation(
        JsonObject movement,
        string legacyName,
        string currentName,
        Func<JsonNode?, string?> promoteMotion)
    {
        JsonObject source = movement[legacyName] as JsonObject ?? new JsonObject();
        JsonObject directions = source["directionMotionIDs"] as JsonObject ?? new JsonObject();
        var promotedDirections = new JsonObject();
        foreach (string name in new[] { "left", "right", "up", "down", "upLeft", "upRight", "downLeft", "downRight" })
        {
            promotedDirections[name] = promoteMotion(directions[name]);
        }
        movement[currentName] = new JsonObject
        {
            ["fallbackBehaviorID"] = promoteMotion(source["fallbackMotionID"]),
            ["usesDirectionalBehaviors"] = source["usesDirectionalMotions"]?.DeepClone() ?? false,
            ["usesDiagonalBehaviors"] = source["usesDiagonalMotions"]?.DeepClone() ?? false,
            ["directionBehaviorIDs"] = promotedDirections,
        };
        movement.Remove(legacyName);
    }

    private static bool IsSingleMotionBehavior(JsonObject sequence, out string? motionId)
    {
        motionId = null;
        if (sequence["steps"] is not JsonArray { Count: 1 } steps ||
            steps[0] is not JsonObject step ||
            step["repeatCount"]?.GetValue<int>() != 1)
        {
            return false;
        }
        motionId = step["motionID"]?.GetValue<string?>();
        return !string.IsNullOrWhiteSpace(motionId);
    }

    private static int HighestPriority(JsonArray rules, string conditionType) =>
        rules.OfType<JsonObject>()
            .Where(rule => string.Equals(
                (rule["condition"] as JsonObject)?["type"]?.GetValue<string?>(),
                conditionType,
                StringComparison.Ordinal))
            .Select(rule => rule["priority"]?.GetValue<int>() ?? 0)
            .DefaultIfEmpty(int.MinValue)
            .Max();

    private static string Base64Url(string value) =>
        Convert.ToBase64String(Encoding.UTF8.GetBytes(value))
            .TrimEnd('=')
            .Replace('+', '-')
            .Replace('/', '_');

    private static double ReadDoubleOr(JsonNode? node, double fallback)
    {
        if (node is JsonValue value)
        {
            if (value.TryGetValue(out double doubleValue)) return doubleValue;
            if (value.TryGetValue(out long longValue)) return longValue;
            if (value.TryGetValue(out int intValue)) return intValue;
        }
        return fallback;
    }

    private static long ReadLongOr(JsonNode? node, long fallback)
    {
        if (node is JsonValue value)
        {
            if (value.TryGetValue(out long longValue)) return longValue;
            if (value.TryGetValue(out int intValue)) return intValue;
        }
        return fallback;
    }

    private static bool ReadBoolOr(JsonNode? node, bool fallback) =>
        node is JsonValue value && value.TryGetValue(out bool result) ? result : fallback;

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
