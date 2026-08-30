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

public sealed record PortablePetDisplaySettings(
    double ScalePercent,
    bool ClickThrough,
    double Opacity,
    bool PointerOverlapFadeEnabled,
    double PointerOverlapOpacity,
    bool PixelArtRendering)
{
    public static readonly PortablePetDisplaySettings Default = FromOverlay(
        OverlaySettings.Default);

    public static PortablePetDisplaySettings FromOverlay(OverlaySettings overlay) => new(
        overlay.Width / AppSettingsLimits.DefaultOverlayWidth * 100,
        overlay.ClickThrough,
        overlay.Opacity,
        overlay.PointerOverlapFadeEnabled,
        overlay.PointerOverlapOpacity,
        overlay.PixelArtRendering);

    public OverlaySettings ApplyTo(OverlaySettings overlay) => overlay with
    {
        Width = AppSettingsLimits.DefaultOverlayWidth * ScalePercent / 100,
        ClickThrough = ClickThrough,
        Opacity = Opacity,
        PointerOverlapFadeEnabled = PointerOverlapFadeEnabled,
        PointerOverlapOpacity = PointerOverlapOpacity,
        PixelArtRendering = PixelArtRendering,
    };
}

public sealed record DecodedRecommendedPetProfile(
    BehaviorProfile Profile,
    PortablePetDisplaySettings Display,
    bool IncludesDisplaySettings);

public static class RecommendedPetProfileCodec
{
    public const int CurrentSchemaVersion = 11;
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
        IReadOnlyCollection<string> availableMotionIds) =>
        DecodeWithDisplay(data, targetKey, availableMotionIds).Profile;

    public static DecodedRecommendedPetProfile DecodeWithDisplay(
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

        int appSettingsSchemaVersion = schemaVersion switch
        {
            <= 7 => 11,
            8 => 12,
            9 => 13,
            10 => 14,
            _ => 15,
        };
        JsonObject profile = behavior.DeepClone().AsObject();
        profile["petKey"] = new JsonObject
        {
            ["type"] = "installed",
            ["installationID"] = PlaceholderInstallationId.ToString("D"),
        };
        profile["automaticRules"] = source["automaticRules"]?.DeepClone() ?? new JsonArray();
        if (schemaVersion >= 8)
        {
            profile["automaticRulePriorityOrder"] =
                source["automaticRulePriorityOrder"]?.DeepClone();
        }
        profile["movement"] = source["movement"]?.DeepClone();
        if (schemaVersion >= 8)
        {
            profile["pettingBehaviorID"] = source["pettingBehaviorID"]?.DeepClone();
        }
        else
        {
            profile["pettingMotionID"] = source["pettingMotionID"]?.DeepClone();
        }
        profile["speech"] = source["speech"]?.DeepClone();
        JsonObject wrapper = Wrapper(profile, appSettingsSchemaVersion);
        if (appSettingsSchemaVersion < AppSettingsStore.CurrentSchemaVersion)
        {
            wrapper = AppSettingsMigrator.Migrate(
                wrapper,
                appSettingsSchemaVersion,
                legacyMotionCycleMillisecondsResolver: null).Document;
        }
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
        PortablePetDisplaySettings display = schemaVersion >= 10
            ? ReadDisplay(source["display"])
            : PortablePetDisplaySettings.Default;
        return new DecodedRecommendedPetProfile(
            decoded,
            display,
            schemaVersion >= 10);
    }

    public static byte[] Encode(
        BehaviorProfile profile,
        IReadOnlyCollection<string> availableMotionIds,
        bool includesApplicationRules,
        OverlaySettings? displaySettings = null)
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
            ["stationaryBehaviorMode"] = stored["stationaryBehaviorMode"]?.DeepClone(),
            ["stationarySequenceID"] = stored["stationarySequenceID"]?.DeepClone(),
            ["randomSequenceIDs"] = stored["randomSequenceIDs"]?.DeepClone(),
            ["sequences"] = stored["sequences"]?.DeepClone(),
        };
        OverlaySettings display = displaySettings ?? OverlaySettings.Default;
        var result = new JsonObject
        {
            ["schemaVersion"] = CurrentSchemaVersion,
            ["behavior"] = behavior,
            ["movement"] = stored["movement"]?.DeepClone(),
            ["pettingBehaviorID"] = stored["pettingBehaviorID"]?.DeepClone(),
            ["automaticRules"] = stored["automaticRules"]?.DeepClone(),
            ["automaticRulePriorityOrder"] =
                stored["automaticRulePriorityOrder"]?.DeepClone(),
            ["speech"] = stored["speech"]?.DeepClone(),
            ["display"] = new JsonObject
            {
                ["scalePercent"] = display.Width / OverlaySettings.Default.Width * 100,
                ["clickThrough"] = display.ClickThrough,
                ["opacity"] = display.Opacity,
                ["pointerOverlapFadeEnabled"] = display.PointerOverlapFadeEnabled,
                ["pointerOverlapOpacity"] = display.PointerOverlapOpacity,
                ["pixelArtRendering"] = display.PixelArtRendering,
            },
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

    private static JsonObject Wrapper(JsonObject profile, int schemaVersion)
    {
        profile["profileID"] = PlaceholderProfileId.ToString("D");
        return new JsonObject
        {
            ["schemaVersion"] = schemaVersion,
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
        var behaviorIds = profile.Sequences
            .Select(sequence => sequence.Id)
            .ToHashSet(StringComparer.Ordinal);
        IEnumerable<string?> movementBehaviors =
        [
            profile.Movement.CursorFollowing.Behavior.FallbackBehaviorId,
            .. profile.Movement.CursorFollowing.Behavior.DirectionBehaviorIds.All,
            profile.Movement.FreeRoaming.Behavior.FallbackBehaviorId,
            .. profile.Movement.FreeRoaming.Behavior.DirectionBehaviorIds.All,
            profile.Movement.CursorAvoiding.Behavior.FallbackBehaviorId,
            .. profile.Movement.CursorAvoiding.Behavior.DirectionBehaviorIds.All,
            profile.Movement.CursorAvoiding.IdleFreeRoaming.Behavior.FallbackBehaviorId,
            .. profile.Movement.CursorAvoiding.IdleFreeRoaming.Behavior.DirectionBehaviorIds.All,
            profile.PettingBehaviorId,
        ];
        string? missingBehavior = movementBehaviors.FirstOrDefault(id =>
            id is not null && !behaviorIds.Contains(id));
        if (missingBehavior is not null)
        {
            throw Error(
                RecommendedPetProfileError.InvalidContent,
                $"권장 설정 행동을 찾을 수 없습니다: {missingBehavior}");
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

    private static PortablePetDisplaySettings ReadDisplay(JsonNode? node)
    {
        if (node is not JsonObject value ||
            !TryDouble(value["scalePercent"], out double scale) ||
            scale is < 10 or > 200 ||
            !TryBool(value["clickThrough"], out bool clickThrough) ||
            !TryDouble(value["opacity"], out double opacity) ||
            opacity is < AppSettingsLimits.MinimumOverlayOpacity or
                > AppSettingsLimits.MaximumOverlayOpacity ||
            !TryBool(value["pointerOverlapFadeEnabled"], out bool overlapFade) ||
            !TryDouble(value["pointerOverlapOpacity"], out double overlapOpacity) ||
            overlapOpacity is < AppSettingsLimits.MinimumPointerOverlapOpacity or
                > AppSettingsLimits.MaximumPointerOverlapOpacity ||
            !TryBool(value["pixelArtRendering"], out bool pixelArt))
        {
            throw Error(
                RecommendedPetProfileError.InvalidContent,
                "권장 표시 설정이 올바르지 않습니다.");
        }
        return new PortablePetDisplaySettings(
            scale,
            clickThrough,
            opacity,
            overlapFade,
            overlapOpacity,
            pixelArt);
    }

    private static bool TryBool(JsonNode? node, out bool value)
    {
        value = default;
        return node is JsonValue json && json.TryGetValue(out value);
    }

    private static bool TryDouble(JsonNode? node, out double value)
    {
        value = default;
        if (node is not JsonValue json)
        {
            return false;
        }
        if (json.TryGetValue(out value)) return double.IsFinite(value);
        if (json.TryGetValue(out int integer))
        {
            value = integer;
            return true;
        }
        if (json.TryGetValue(out long longValue))
        {
            value = longValue;
            return true;
        }
        return false;
    }

    private static RecommendedPetProfileException Error(
        RecommendedPetProfileError error,
        string message,
        Exception? inner = null) => new(error, message, inner);
}
