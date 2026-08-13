using System.Text.Json;
using System.Text.Json.Nodes;
using MonglePet.Core.Behavior;

namespace MonglePet.Settings;

public enum RecommendedPetProfileError
{
    TooLarge,
    InvalidJson,
    UnsupportedSchema,
    InvalidContent,
    MissingMotion,
}

public sealed class RecommendedPetProfileException(
    RecommendedPetProfileError error,
    string message,
    Exception? innerException = null) : Exception(message, innerException)
{
    public RecommendedPetProfileError Error { get; } = error;
}

public static class RecommendedPetProfileCodec
{
    public const int CurrentSchemaVersion = 7;
    public const int MaximumFileSize = 1 * 1024 * 1024;
    private static readonly Guid PlaceholderInstallationId =
        Guid.Parse("00000000-0000-0000-0000-000000000001");
    private static readonly Guid PlaceholderInstanceId =
        Guid.Parse("00000000-0000-0000-0000-000000000002");
    private static readonly Guid PlaceholderProfileId =
        Guid.Parse("00000000-0000-0000-0000-000000000003");

    public static BehaviorProfile Decode(
        ReadOnlySpan<byte> data,
        PetBehaviorKey targetKey,
        IReadOnlyCollection<string> availableMotionIds)
    {
        if (data.Length > MaximumFileSize)
        {
            throw Error(RecommendedPetProfileError.TooLarge, "권장 설정 파일이 1 MiB를 초과합니다.");
        }
        JsonObject source;
        try
        {
            source = JsonNode.Parse(data)?.AsObject()
                ?? throw Error(RecommendedPetProfileError.InvalidJson, "권장 설정 JSON이 올바르지 않습니다.");
        }
        catch (RecommendedPetProfileException)
        {
            throw;
        }
        catch (Exception exception) when (exception is JsonException or InvalidOperationException)
        {
            throw Error(RecommendedPetProfileError.InvalidJson, "권장 설정 JSON이 올바르지 않습니다.", exception);
        }

        int schemaVersion;
        try
        {
            schemaVersion = source["schemaVersion"]?.GetValue<int>() ?? 0;
        }
        catch (InvalidOperationException exception)
        {
            throw Error(
                RecommendedPetProfileError.InvalidJson,
                "The recommended profile schema version is invalid.",
                exception);
        }
        if (schemaVersion is < 1 or > CurrentSchemaVersion)
        {
            throw Error(
                RecommendedPetProfileError.UnsupportedSchema,
                $"지원하지 않는 권장 설정 버전입니다: {schemaVersion}");
        }
        if (source["behavior"] is not JsonObject behavior)
        {
            throw Error(RecommendedPetProfileError.InvalidContent, "권장 행동 설정이 없습니다.");
        }

        NormalizeLegacyProfile(source, schemaVersion);

        JsonObject profile = behavior.DeepClone().AsObject();
        profile["petKey"] = new JsonObject
        {
            ["type"] = "installed",
            ["installationID"] = PlaceholderInstallationId.ToString("D"),
        };
        profile["automaticRules"] = source["automaticRules"]?.DeepClone() ?? new JsonArray();
        profile["movement"] = source["movement"]?.DeepClone();
        profile["pettingMotionID"] = source["pettingMotionID"]?.DeepClone();
        profile["speech"] = source["speech"]?.DeepClone();
        JsonObject wrapper = Wrapper(profile);
        AppSettingsDocumentMappingResult mapping = AppSettingsDocumentMapper.FromDocument(wrapper);
        if (mapping.Issues.Count > 0 || mapping.Settings.BehaviorProfiles.Count != 1)
        {
            throw Error(
                RecommendedPetProfileError.InvalidContent,
                mapping.Issues.Count == 0
                    ? "권장 설정을 읽을 수 없습니다."
                    : string.Join(" ", mapping.Issues));
        }

        BehaviorProfile decoded = mapping.Settings.BehaviorProfiles[0] with { PetKey = targetKey };
        ValidateMotionReferences(decoded, availableMotionIds);
        return decoded;
    }

    public static byte[] Encode(
        BehaviorProfile profile,
        IReadOnlyCollection<string> availableMotionIds,
        bool includesApplicationRules)
    {
        ArgumentNullException.ThrowIfNull(profile);
        ValidateMotionReferences(profile, availableMotionIds);
        BehaviorProfile exportProfile = profile with
        {
            PetKey = new PetBehaviorKey.Installed(PlaceholderInstallationId),
            AutomaticRules = includesApplicationRules
                ? profile.AutomaticRules
                : profile.AutomaticRules
                    .Where(rule => rule.Condition is not RuleCondition.Application)
                    .ToList(),
        };
        JsonObject full = AppSettingsDocumentMapper.ToDocument(
            new AppSettings(
                [new ActivePetInstance(
                    PlaceholderInstanceId,
                    exportProfile.ProfileId,
                    exportProfile.PetKey,
                    null,
                    PetPresentation.Awake,
                    OverlaySettings.Default,
                    0)],
                [exportProfile],
                PlaceholderInstanceId),
            null);
        JsonObject stored = full["behaviorProfiles"]!.AsArray()[0]!.AsObject();
        var behavior = new JsonObject
        {
            ["mode"] = stored["mode"]?.DeepClone(),
            ["manualSequenceID"] = stored["manualSequenceID"]?.DeepClone(),
            ["sequences"] = stored["sequences"]?.DeepClone(),
        };
        var result = new JsonObject
        {
            ["schemaVersion"] = CurrentSchemaVersion,
            ["behavior"] = behavior,
            ["movement"] = stored["movement"]?.DeepClone(),
            ["pettingMotionID"] = stored["pettingMotionID"]?.DeepClone(),
            ["automaticRules"] = stored["automaticRules"]?.DeepClone(),
            ["speech"] = stored["speech"]?.DeepClone(),
        };
        byte[] data = JsonSerializer.SerializeToUtf8Bytes(
            result,
            new JsonSerializerOptions { WriteIndented = true });
        if (data.Length > MaximumFileSize)
        {
            throw Error(RecommendedPetProfileError.TooLarge, "권장 설정 파일이 1 MiB를 초과합니다.");
        }
        return data;
    }

    private static JsonObject Wrapper(JsonObject profile)
    {
        profile["profileID"] = PlaceholderProfileId.ToString("D");
        return new JsonObject
        {
            ["schemaVersion"] = AppSettingsStore.CurrentSchemaVersion,
            ["selectedPetInstanceID"] = PlaceholderInstanceId.ToString("D"),
            ["activePetInstances"] = new JsonArray(new JsonObject
            {
                ["instanceID"] = PlaceholderInstanceId.ToString("D"),
                ["behaviorProfileID"] = PlaceholderProfileId.ToString("D"),
                ["petKey"] = profile["petKey"]!.DeepClone(),
                ["nickname"] = null,
                ["presentation"] = "awake",
                ["overlay"] = new JsonObject(),
                ["displayOrder"] = 0,
            }),
            ["behaviorProfiles"] = new JsonArray(profile),
        };
    }

    private static void NormalizeLegacyProfile(JsonObject source, int schemaVersion)
    {
        if (schemaVersion == 1 && source["movement"] is JsonObject movement)
        {
            movement["cursorFollowingAnimation"] ??= LegacyAnimation(
                movement["cursorFollowingMotionID"]);
            movement["freeRoamingAnimation"] ??= LegacyAnimation(
                movement["freeRoamingMotionID"]);
        }

        if (schemaVersion is < 4 or > 5 || source["speech"] is not JsonObject speech)
        {
            return;
        }

        JsonArray? phrases = speech["phrases"] as JsonArray;
        speech["periodicIsEnabled"] ??= phrases?.Any(node =>
            node is JsonObject phrase &&
            phrase["trigger"] is JsonObject trigger &&
            string.Equals(
                trigger["type"]?.GetValue<string>(),
                "periodic",
                StringComparison.Ordinal)) ?? false;
        speech["periodicOrder"] ??= "random";
        speech["behaviorChangePolicy"] ??= "dismiss";
        if (phrases is null)
        {
            return;
        }

        foreach (JsonObject phrase in phrases.OfType<JsonObject>())
        {
            phrase["displayMode"] ??= "timed";
        }
    }

    private static JsonObject LegacyAnimation(JsonNode? fallbackMotionId) => new()
    {
        ["fallbackMotionID"] = fallbackMotionId?.DeepClone(),
        ["usesDirectionalMotions"] = false,
        ["usesDiagonalMotions"] = false,
        ["directionMotionIDs"] = new JsonObject(),
    };

    private static void ValidateMotionReferences(
        BehaviorProfile profile,
        IReadOnlyCollection<string> availableMotionIds)
    {
        var motions = availableMotionIds.ToHashSet(StringComparer.Ordinal);
        bool Available(string? id) => id is null || motions.Contains(id);
        foreach (BehaviorStep step in profile.Sequences.SelectMany(sequence => sequence.Steps))
        {
            if (!string.Equals(step.MotionId, BehaviorMotionReferences.CurrentPetDefault, StringComparison.Ordinal) &&
                !motions.Contains(step.MotionId))
            {
                throw Error(RecommendedPetProfileError.MissingMotion, $"권장 설정 모션을 찾을 수 없습니다: {step.MotionId}");
            }
        }
        IEnumerable<string?> movementMotions =
        [
            profile.Movement.CursorFollowingAnimation.FallbackMotionId,
            .. profile.Movement.CursorFollowingAnimation.DirectionMotionIds.All,
            profile.Movement.FreeRoamingAnimation.FallbackMotionId,
            .. profile.Movement.FreeRoamingAnimation.DirectionMotionIds.All,
            profile.Movement.CursorAvoidingAnimation.FallbackMotionId,
            .. profile.Movement.CursorAvoidingAnimation.DirectionMotionIds.All,
            profile.PettingMotionId,
        ];
        string? missing = movementMotions.FirstOrDefault(id => !Available(id));
        if (missing is not null)
        {
            throw Error(RecommendedPetProfileError.MissingMotion, $"권장 설정 모션을 찾을 수 없습니다: {missing}");
        }
    }

    private static RecommendedPetProfileException Error(
        RecommendedPetProfileError error,
        string message,
        Exception? inner = null) => new(error, message, inner);
}
