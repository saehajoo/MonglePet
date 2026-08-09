using System.Text.Json.Nodes;
using MonglePet.Core.Behavior;

namespace MonglePet.Settings;

internal sealed record AppSettingsDocumentMappingResult(
    AppSettings Settings,
    IReadOnlyList<SettingsRecoveryIssue> Issues);

internal static class AppSettingsDocumentMapper
{
    public static AppSettingsDocumentMappingResult FromDocument(JsonObject document)
    {
        var issues = new List<SettingsRecoveryIssue>();
        Guid? selectedId = ReadOptionalGuid(
            document,
            "selectedPetInstallationID",
            "selectedPetInstallationID",
            issues);
        PetPresentation presentation = ReadEnum(
            document,
            "lastUserPresentation",
            new Dictionary<string, PetPresentation>(StringComparer.Ordinal)
            {
                ["awake"] = PetPresentation.Awake,
                ["tuckedAway"] = PetPresentation.TuckedAway,
            },
            PetPresentation.Awake,
            "lastUserPresentation",
            issues);
        OverlaySettings overlay = ReadOverlay(document["overlay"], issues);
        IReadOnlyList<BehaviorProfile> profiles = ReadProfiles(
            document["behaviorProfiles"],
            issues);
        return new AppSettingsDocumentMappingResult(
            new AppSettings(selectedId, presentation, overlay, profiles),
            issues);
    }

    public static JsonObject ToDocument(AppSettings settings, JsonObject? template)
    {
        Validate(settings);
        JsonObject document = template?.DeepClone().AsObject() ?? new JsonObject();
        document["schemaVersion"] = AppSettingsStore.CurrentSchemaVersion;
        document["selectedPetInstallationID"] = settings.SelectedPetInstallationId?.ToString("D");
        document["lastUserPresentation"] = settings.LastUserPresentation == PetPresentation.Awake
            ? "awake"
            : "tuckedAway";
        document["overlay"] = WriteOverlay(
            settings.Overlay,
            template?["overlay"] as JsonObject);

        var profiles = new JsonArray();
        foreach (BehaviorProfile profile in settings.BehaviorProfiles)
        {
            profiles.Add(WriteProfile(profile, FindProfileTemplate(template, profile.PetKey)));
        }
        document["behaviorProfiles"] = profiles;
        return document;
    }

    private static OverlaySettings ReadOverlay(
        JsonNode? node,
        List<SettingsRecoveryIssue> issues)
    {
        JsonObject? value = node as JsonObject;
        if (node is not null && value is null)
        {
            Invalid("overlay", issues);
        }
        value ??= new JsonObject();
        string? screenIdentifier = ReadOptionalIdentifier(
            value,
            "screenIdentifier",
            "overlay.screenIdentifier",
            issues,
            requireUnmodified: false);
        double originX = ReadFinite(
            value,
            "originX",
            OverlaySettings.Default.OriginX,
            "overlay.originX",
            issues);
        double originY = ReadFinite(
            value,
            "originY",
            OverlaySettings.Default.OriginY,
            "overlay.originY",
            issues);
        double width = ReadClamped(
            value,
            "width",
            AppSettingsLimits.MinimumOverlayWidth,
            AppSettingsLimits.MaximumOverlayWidth,
            AppSettingsLimits.DefaultOverlayWidth,
            "overlay.width",
            issues);
        double opacity = ReadRanged(
            value,
            "opacity",
            AppSettingsLimits.MinimumOverlayOpacity,
            AppSettingsLimits.MaximumOverlayOpacity,
            AppSettingsLimits.DefaultOverlayOpacity,
            "overlay.opacity",
            issues);
        double pointerOpacity = ReadRanged(
            value,
            "pointerOverlapOpacity",
            AppSettingsLimits.MinimumPointerOverlapOpacity,
            AppSettingsLimits.MaximumPointerOverlapOpacity,
            AppSettingsLimits.DefaultPointerOverlapOpacity,
            "overlay.pointerOverlapOpacity",
            issues);
        return new OverlaySettings(
            screenIdentifier,
            originX,
            originY,
            width,
            ReadBool(value, "clickThrough", false, "overlay.clickThrough", issues),
            opacity,
            ReadBool(
                value,
                "pointerOverlapFadeEnabled",
                false,
                "overlay.pointerOverlapFadeEnabled",
                issues),
            pointerOpacity,
            ReadBool(
                value,
                "pixelArtRendering",
                false,
                "overlay.pixelArtRendering",
                issues),
            ReadMovementBoundary(value["movementBoundary"], issues));
    }

    private static MovementBoundarySettings ReadMovementBoundary(
        JsonNode? node,
        List<SettingsRecoveryIssue> issues)
    {
        if (node is null)
        {
            return MovementBoundarySettings.Default;
        }
        if (node is not JsonObject value)
        {
            Invalid("overlay.movementBoundary", issues);
            return MovementBoundarySettings.Default;
        }
        MovementBoundaryMode? mode = ReadOptionalEnum(
            value,
            "mode",
            new Dictionary<string, MovementBoundaryMode>(StringComparer.Ordinal)
            {
                ["allDisplays"] = MovementBoundaryMode.AllDisplays,
                ["selectedDisplay"] = MovementBoundaryMode.SelectedDisplay,
                ["customArea"] = MovementBoundaryMode.CustomArea,
            },
            "overlay.movementBoundary.mode",
            issues);
        if (mode is null)
        {
            return MovementBoundarySettings.Default;
        }
        string? screen = ReadOptionalIdentifier(
            value,
            "screenIdentifier",
            "overlay.movementBoundary.screenIdentifier",
            issues,
            requireUnmodified: false);
        NormalizedMovementRect? rect = ReadNormalizedRect(value["normalizedRect"], issues);
        bool valid = mode switch
        {
            MovementBoundaryMode.AllDisplays => true,
            MovementBoundaryMode.SelectedDisplay => screen is not null,
            MovementBoundaryMode.CustomArea => screen is not null && rect is not null,
            _ => false,
        };
        if (!valid)
        {
            Invalid("overlay.movementBoundary", issues);
            return MovementBoundarySettings.Default;
        }
        return new MovementBoundarySettings(mode.Value, screen, rect);
    }

    private static NormalizedMovementRect? ReadNormalizedRect(
        JsonNode? node,
        List<SettingsRecoveryIssue> issues)
    {
        if (node is null)
        {
            return null;
        }
        if (node is not JsonObject value ||
            !TryDouble(value["x"], out double x) ||
            !TryDouble(value["y"], out double y) ||
            !TryDouble(value["width"], out double width) ||
            !TryDouble(value["height"], out double height))
        {
            Invalid("overlay.movementBoundary.normalizedRect", issues);
            return null;
        }
        var rect = new NormalizedMovementRect(x, y, width, height);
        if (!rect.IsValid)
        {
            Invalid("overlay.movementBoundary.normalizedRect", issues);
            return null;
        }
        return rect;
    }

    private static IReadOnlyList<BehaviorProfile> ReadProfiles(
        JsonNode? node,
        List<SettingsRecoveryIssue> issues)
    {
        if (node is null)
        {
            return [];
        }
        if (node is not JsonArray values)
        {
            Invalid("behaviorProfiles", issues);
            return [];
        }
        if (values.Count > AppSettingsLimits.MaximumBehaviorProfiles)
        {
            Truncated("behaviorProfiles", issues);
        }
        var seenKeys = new HashSet<PetBehaviorKey>();
        var profiles = new List<BehaviorProfile>();
        for (int index = 0; index < Math.Min(values.Count, AppSettingsLimits.MaximumBehaviorProfiles); index++)
        {
            string field = $"behaviorProfiles.{index}";
            if (values[index] is not JsonObject value ||
                !TryReadPetKey(value["petKey"], out PetBehaviorKey key) ||
                !seenKeys.Add(key))
            {
                Invalid($"{field}.petKey", issues);
                continue;
            }
            BehaviorMode mode = ReadEnum(
                value,
                "mode",
                new Dictionary<string, BehaviorMode>(StringComparer.Ordinal)
                {
                    ["automatic"] = BehaviorMode.Automatic,
                    ["manual"] = BehaviorMode.Manual,
                },
                BehaviorMode.Automatic,
                $"{field}.mode",
                issues);
            IReadOnlyList<BehaviorSequence> sequences = ReadSequences(
                value["sequences"],
                $"{field}.sequences",
                issues);
            var sequenceIds = sequences.Select(sequence => sequence.Id).ToHashSet(StringComparer.Ordinal);
            string? manual = ReadOptionalIdentifier(
                value,
                "manualSequenceID",
                $"{field}.manualSequenceID",
                issues,
                requireUnmodified: false);
            if (manual is not null && !sequenceIds.Contains(manual))
            {
                Invalid($"{field}.manualSequenceID", issues);
                manual = null;
            }
            profiles.Add(new BehaviorProfile(
                key,
                mode,
                manual,
                sequences,
                ReadRules(value["automaticRules"], sequenceIds, $"{field}.automaticRules", issues),
                ReadMovement(value["movement"], $"{field}.movement", issues),
                ReadOptionalIdentifier(
                    value,
                    "pettingMotionID",
                    $"{field}.pettingMotionID",
                    issues,
                    requireUnmodified: true),
                ReadSpeech(value["speech"], sequenceIds, $"{field}.speech", issues)));
        }
        return profiles;
    }

    private static IReadOnlyList<BehaviorSequence> ReadSequences(
        JsonNode? node,
        string field,
        List<SettingsRecoveryIssue> issues)
    {
        if (node is null)
        {
            return [];
        }
        if (node is not JsonArray values)
        {
            Invalid(field, issues);
            return [];
        }
        if (values.Count > AppSettingsLimits.MaximumSequences)
        {
            Truncated(field, issues);
        }
        var seenIds = new HashSet<string>(StringComparer.Ordinal);
        var sequences = new List<BehaviorSequence>();
        foreach (JsonNode? nodeValue in values.Take(AppSettingsLimits.MaximumSequences))
        {
            JsonObject? value = nodeValue as JsonObject;
            if (value is null ||
                !TryNormalizedIdentifier(value["id"], out string id) ||
                !seenIds.Add(id))
            {
                issues.Add(new SettingsRecoveryIssue(
                    SettingsRecoveryKind.DroppedSequence,
                    ReadDisplayValue(value?["id"])));
                continue;
            }
            string stepField = $"{field}.{id}.steps";
            var steps = new List<BehaviorStep>();
            if (value["steps"] is JsonArray storedSteps)
            {
                if (storedSteps.Count > AppSettingsLimits.MaximumStepsPerSequence)
                {
                    Truncated(stepField, issues);
                }
                foreach (JsonNode? stepNode in storedSteps.Take(AppSettingsLimits.MaximumStepsPerSequence))
                {
                    if (stepNode is JsonObject step &&
                        TryNormalizedIdentifier(step["motionID"], out string motionId) &&
                        TryInt(step["repeatCount"], out int repeatCount) &&
                        repeatCount is >= 1 and <= AppSettingsLimits.MaximumRepeatCount)
                    {
                        steps.Add(new BehaviorStep(motionId, repeatCount));
                    }
                    else
                    {
                        Invalid(stepField, issues);
                    }
                }
            }
            else if (value["steps"] is not null)
            {
                Invalid(stepField, issues);
            }
            if (steps.Count == 0)
            {
                issues.Add(new SettingsRecoveryIssue(SettingsRecoveryKind.DroppedSequence, id));
                continue;
            }
            sequences.Add(new BehaviorSequence(
                id,
                steps,
                ReadBool(value, "repeats", false, $"{field}.{id}.repeats", issues)));
        }
        return sequences;
    }

    private static IReadOnlyList<AutomaticRule> ReadRules(
        JsonNode? node,
        ISet<string> sequenceIds,
        string field,
        List<SettingsRecoveryIssue> issues)
    {
        if (node is null)
        {
            return [];
        }
        if (node is not JsonArray values)
        {
            Invalid(field, issues);
            return [];
        }
        if (values.Count > AppSettingsLimits.MaximumAutomaticRules)
        {
            Truncated(field, issues);
        }
        var seenIds = new HashSet<Guid>();
        var rules = new List<AutomaticRule>();
        foreach (JsonNode? nodeValue in values.Take(AppSettingsLimits.MaximumAutomaticRules))
        {
            JsonObject? value = nodeValue as JsonObject;
            if (value is null ||
                !TryGuid(value["id"], out Guid id) ||
                !seenIds.Add(id) ||
                !TryNormalizedIdentifier(value["sequenceID"], out string sequenceId))
            {
                issues.Add(new SettingsRecoveryIssue(
                    SettingsRecoveryKind.DroppedRule,
                    ReadDisplayValue(value?["id"])));
                continue;
            }
            bool storedEnabled = ReadBool(value, "isEnabled", false, $"{field}.{id:D}.isEnabled", issues);
            bool enabled = storedEnabled;
            RuleCondition condition;
            if (value["condition"] is not JsonObject storedCondition ||
                !TryString(storedCondition["type"], out string conditionType))
            {
                condition = new RuleCondition.Unsupported("unknown");
                enabled = false;
                Invalid($"{field}.{id:D}.condition", issues);
            }
            else if (string.Equals(conditionType, "application", StringComparison.Ordinal))
            {
                string? applicationId = ReadOptionalIdentifier(
                    storedCondition,
                    "bundleIdentifier",
                    $"{field}.{id:D}.condition.bundleIdentifier",
                    issues,
                    requireUnmodified: false);
                condition = new RuleCondition.Application(applicationId ?? string.Empty);
                enabled &= applicationId is not null;
            }
            else if (string.Equals(conditionType, "idleAtLeast", StringComparison.Ordinal))
            {
                long milliseconds = ReadLong(
                    storedCondition,
                    "milliseconds",
                    0,
                    $"{field}.{id:D}.condition.milliseconds",
                    issues);
                condition = new RuleCondition.IdleAtLeast(milliseconds);
                enabled &= milliseconds is >= 1 and <= AppSettingsLimits.MaximumDurationMilliseconds;
            }
            else
            {
                string unsupportedType = conditionType.Trim();
                if (unsupportedType.Length == 0 || unsupportedType != conditionType)
                {
                    Invalid($"{field}.{id:D}.condition.type", issues);
                    unsupportedType = unsupportedType.Length == 0
                        ? "unknown"
                        : unsupportedType;
                }
                condition = new RuleCondition.Unsupported(unsupportedType);
                enabled = false;
            }
            enabled &= sequenceIds.Contains(sequenceId);
            if (storedEnabled && !enabled)
            {
                issues.Add(new SettingsRecoveryIssue(SettingsRecoveryKind.DisabledRule, id.ToString("D")));
            }
            rules.Add(new AutomaticRule(
                id,
                enabled,
                ReadInt(value, "priority", 0, $"{field}.{id:D}.priority", issues),
                condition,
                sequenceId));
        }
        return rules;
    }

    private static PetMovementSettings ReadMovement(
        JsonNode? node,
        string field,
        List<SettingsRecoveryIssue> issues)
    {
        if (node is null)
        {
            return PetMovementSettings.Default;
        }
        if (node is not JsonObject value)
        {
            Invalid(field, issues);
            return PetMovementSettings.Default;
        }
        return new PetMovementSettings(
            ReadEnum(
                value,
                "mode",
                new Dictionary<string, PetMovementMode>(StringComparer.Ordinal)
                {
                    ["fixed"] = PetMovementMode.Fixed,
                    ["cursorFollowing"] = PetMovementMode.CursorFollowing,
                    ["freeRoaming"] = PetMovementMode.FreeRoaming,
                    ["cursorAvoiding"] = PetMovementMode.CursorAvoiding,
                },
                PetMovementMode.Fixed,
                $"{field}.mode",
                issues),
            ReadRanged(value, "speed", 20, 1_000, 160, $"{field}.speed", issues),
            ReadRanged(value, "cursorDistance", 0, 512, 96, $"{field}.cursorDistance", issues),
            ReadRanged(value, "stopRadius", 0, 128, 16, $"{field}.stopRadius", issues),
            ReadRangedLong(value, "freeRoamingDwellMilliseconds", 500, 300_000, 6_000, $"{field}.freeRoamingDwellMilliseconds", issues),
            ReadBool(value, "prefersFrontmostWindow", true, $"{field}.prefersFrontmostWindow", issues),
            ReadAnimation(value["cursorFollowingAnimation"], $"{field}.cursorFollowingAnimation", issues),
            ReadAnimation(value["freeRoamingAnimation"], $"{field}.freeRoamingAnimation", issues),
            ReadEnum(
                value,
                "cursorAvoidingIdleBehavior",
                new Dictionary<string, CursorAvoidingIdleBehavior>(StringComparer.Ordinal)
                {
                    ["stationary"] = CursorAvoidingIdleBehavior.Stationary,
                    ["freeRoaming"] = CursorAvoidingIdleBehavior.FreeRoaming,
                },
                CursorAvoidingIdleBehavior.Stationary,
                $"{field}.cursorAvoidingIdleBehavior",
                issues),
            ReadRanged(value, "cursorAvoidingDetectionDistance", 32, 1_024, 160, $"{field}.cursorAvoidingDetectionDistance", issues),
            ReadRanged(value, "cursorAvoidingSpeed", 20, 1_000, 320, $"{field}.cursorAvoidingSpeed", issues),
            ReadAnimation(value["cursorAvoidingAnimation"], $"{field}.cursorAvoidingAnimation", issues));
    }

    private static MovementAnimationSettings ReadAnimation(
        JsonNode? node,
        string field,
        List<SettingsRecoveryIssue> issues)
    {
        if (node is null)
        {
            return MovementAnimationSettings.Default;
        }
        if (node is not JsonObject value)
        {
            Invalid(field, issues);
            return MovementAnimationSettings.Default;
        }
        bool directional = ReadBool(value, "usesDirectionalMotions", false, $"{field}.usesDirectionalMotions", issues);
        bool diagonal = ReadBool(value, "usesDiagonalMotions", false, $"{field}.usesDiagonalMotions", issues);
        if (diagonal && !directional)
        {
            diagonal = false;
            Invalid($"{field}.usesDiagonalMotions", issues);
        }
        JsonObject directions = value["directionMotionIDs"] as JsonObject ?? new JsonObject();
        if (value["directionMotionIDs"] is not null && value["directionMotionIDs"] is not JsonObject)
        {
            Invalid($"{field}.directionMotionIDs", issues);
        }
        string? Motion(string name) => ReadOptionalIdentifier(
            directions,
            name,
            $"{field}.directionMotionIDs.{name}",
            issues,
            requireUnmodified: true);
        return new MovementAnimationSettings(
            ReadOptionalIdentifier(value, "fallbackMotionID", $"{field}.fallbackMotionID", issues, true),
            directional,
            diagonal,
            new DirectionalMotionIds(
                Motion("left"), Motion("right"), Motion("up"), Motion("down"),
                Motion("upLeft"), Motion("upRight"), Motion("downLeft"), Motion("downRight")));
    }

    private static PetSpeechSettings ReadSpeech(
        JsonNode? node,
        ISet<string> sequenceIds,
        string field,
        List<SettingsRecoveryIssue> issues)
    {
        if (node is null)
        {
            return PetSpeechSettings.Default;
        }
        if (node is not JsonObject value)
        {
            Invalid(field, issues);
            return PetSpeechSettings.Default;
        }
        return new PetSpeechSettings(
            ReadBool(value, "isEnabled", false, $"{field}.isEnabled", issues),
            ReadBool(value, "periodicIsEnabled", false, $"{field}.periodicIsEnabled", issues),
            ReadRangedLong(value, "periodicIntervalMilliseconds", 5_000, 3_600_000, 60_000, $"{field}.periodicIntervalMilliseconds", issues),
            ReadEnum(
                value,
                "periodicOrder",
                new Dictionary<string, PetSpeechPeriodicOrder>(StringComparer.Ordinal)
                {
                    ["random"] = PetSpeechPeriodicOrder.Random,
                    ["sequential"] = PetSpeechPeriodicOrder.Sequential,
                },
                PetSpeechPeriodicOrder.Random,
                $"{field}.periodicOrder",
                issues),
            ReadEnum(
                value,
                "behaviorChangePolicy",
                new Dictionary<string, PetSpeechBehaviorChangePolicy>(StringComparer.Ordinal)
                {
                    ["dismiss"] = PetSpeechBehaviorChangePolicy.Dismiss,
                    ["keep"] = PetSpeechBehaviorChangePolicy.Keep,
                },
                PetSpeechBehaviorChangePolicy.Dismiss,
                $"{field}.behaviorChangePolicy",
                issues),
            ReadPhrases(value["phrases"], sequenceIds, $"{field}.phrases", issues),
            ReadTheme(value["theme"], $"{field}.theme", issues),
            ReadPlacement(value["placement"], $"{field}.placement", issues));
    }

    private static IReadOnlyList<PetSpeechPhrase> ReadPhrases(
        JsonNode? node,
        ISet<string> sequenceIds,
        string field,
        List<SettingsRecoveryIssue> issues)
    {
        if (node is null)
        {
            return [];
        }
        if (node is not JsonArray values)
        {
            Invalid(field, issues);
            return [];
        }
        if (values.Count > AppSettingsLimits.MaximumSpeechPhrases)
        {
            Truncated(field, issues);
        }
        var seenIds = new HashSet<Guid>();
        var phrases = new List<PetSpeechPhrase>();
        for (int index = 0; index < Math.Min(values.Count, AppSettingsLimits.MaximumSpeechPhrases); index++)
        {
            string phraseField = $"{field}.{index}";
            if (values[index] is not JsonObject value ||
                !TryGuid(value["id"], out Guid id) ||
                !seenIds.Add(id) ||
                !TryString(value["text"], out string text) ||
                string.IsNullOrWhiteSpace(text) || text.Trim() != text ||
                AppSettingsLimits.TextLength(text) > AppSettingsLimits.MaximumSpeechTextLength ||
                !TryLong(value["displayDurationMilliseconds"], out long duration) ||
                duration is < 1_000 or > 30_000 ||
                value["trigger"] is not JsonObject trigger ||
                !TryString(trigger["type"], out string type))
            {
                Invalid(phraseField, issues);
                continue;
            }
            PetSpeechTrigger mappedTrigger;
            if (string.Equals(type, "periodic", StringComparison.Ordinal) && trigger["sequenceID"] is null)
            {
                mappedTrigger = new PetSpeechTrigger.Periodic();
            }
            else if (string.Equals(type, "sequence", StringComparison.Ordinal) &&
                TryNormalizedIdentifier(trigger["sequenceID"], out string sequenceId) &&
                sequenceIds.Contains(sequenceId))
            {
                mappedTrigger = new PetSpeechTrigger.Sequence(sequenceId);
            }
            else
            {
                Invalid($"{phraseField}.trigger", issues);
                continue;
            }
            PetSpeechDisplayMode displayMode = ReadEnum(
                value,
                "displayMode",
                new Dictionary<string, PetSpeechDisplayMode>(StringComparer.Ordinal)
                {
                    ["timed"] = PetSpeechDisplayMode.Timed,
                    ["untilNextPhrase"] = PetSpeechDisplayMode.UntilNextPhrase,
                },
                PetSpeechDisplayMode.Timed,
                $"{phraseField}.displayMode",
                issues);
            phrases.Add(new PetSpeechPhrase(id, text, duration, mappedTrigger, displayMode));
        }
        return phrases;
    }

    private static PetSpeechBubbleTheme ReadTheme(
        JsonNode? node,
        string field,
        List<SettingsRecoveryIssue> issues)
    {
        if (node is null)
        {
            return PetSpeechBubbleTheme.Default;
        }
        if (node is not JsonObject value)
        {
            Invalid(field, issues);
            return PetSpeechBubbleTheme.Default;
        }
        PetSpeechBubbleColorStyle style = ReadEnum(
            value,
            "colorStyle",
            new Dictionary<string, PetSpeechBubbleColorStyle>(StringComparer.Ordinal)
            {
                ["system"] = PetSpeechBubbleColorStyle.System,
                ["cream"] = PetSpeechBubbleColorStyle.Cream,
                ["midnight"] = PetSpeechBubbleColorStyle.Midnight,
                ["mint"] = PetSpeechBubbleColorStyle.Mint,
                ["peach"] = PetSpeechBubbleColorStyle.Peach,
                ["custom"] = PetSpeechBubbleColorStyle.Custom,
            },
            PetSpeechBubbleColorStyle.System,
            $"{field}.colorStyle",
            issues);
        PetSpeechColor background = ReadColor(
            value["customBackgroundColor"],
            PetSpeechColor.White,
            $"{field}.customBackgroundColor",
            issues);
        PetSpeechColor text = ReadColor(
            value["customTextColor"],
            PetSpeechColor.Black,
            $"{field}.customTextColor",
            issues);
        if (style == PetSpeechBubbleColorStyle.Custom &&
            background.ContrastRatio(text) < AppSettingsLimits.MinimumSpeechBubbleTextContrastRatio)
        {
            text = PetSpeechColor.PreferredTextColor(background);
            Invalid($"{field}.customTextColor", issues);
        }
        return new PetSpeechBubbleTheme(
            style,
            background,
            text,
            ReadRanged(value, "backgroundOpacity", 0.65, 1, 0.96, $"{field}.backgroundOpacity", issues),
            ReadRanged(value, "fontSize", 11, 24, 14, $"{field}.fontSize", issues),
            ReadRanged(value, "contentPadding", 6, 24, 12, $"{field}.contentPadding", issues),
            ReadRanged(value, "cornerRadius", 0, 28, 14, $"{field}.cornerRadius", issues),
            ReadBool(value, "showsTail", false, $"{field}.showsTail", issues),
            ReadEnum(
                value,
                "tailAlignment",
                new Dictionary<string, PetSpeechBubbleTailAlignment>(StringComparer.Ordinal)
                {
                    ["leading"] = PetSpeechBubbleTailAlignment.Leading,
                    ["center"] = PetSpeechBubbleTailAlignment.Center,
                    ["trailing"] = PetSpeechBubbleTailAlignment.Trailing,
                },
                PetSpeechBubbleTailAlignment.Center,
                $"{field}.tailAlignment",
                issues));
    }

    private static PetSpeechColor ReadColor(
        JsonNode? node,
        PetSpeechColor fallback,
        string field,
        List<SettingsRecoveryIssue> issues)
    {
        if (node is null)
        {
            return fallback;
        }
        if (node is not JsonObject value ||
            !TryDouble(value["red"], out double red) ||
            !TryDouble(value["green"], out double green) ||
            !TryDouble(value["blue"], out double blue))
        {
            Invalid(field, issues);
            return fallback;
        }
        var color = new PetSpeechColor(red, green, blue);
        if (!color.IsValid)
        {
            Invalid(field, issues);
            return fallback;
        }
        return color;
    }

    private static PetSpeechBubblePlacementSettings ReadPlacement(
        JsonNode? node,
        string field,
        List<SettingsRecoveryIssue> issues)
    {
        if (node is null)
        {
            return PetSpeechBubblePlacementSettings.Default;
        }
        if (node is not JsonObject value)
        {
            Invalid(field, issues);
            return PetSpeechBubblePlacementSettings.Default;
        }
        return new PetSpeechBubblePlacementSettings(
            ReadEnum(
                value,
                "preferredPosition",
                new Dictionary<string, PetSpeechBubblePreferredPosition>(StringComparer.Ordinal)
                {
                    ["automatic"] = PetSpeechBubblePreferredPosition.Automatic,
                    ["above"] = PetSpeechBubblePreferredPosition.Above,
                    ["below"] = PetSpeechBubblePreferredPosition.Below,
                },
                PetSpeechBubblePreferredPosition.Automatic,
                $"{field}.preferredPosition",
                issues),
            ReadClamped(value, "horizontalOffset", -160, 160, 0, $"{field}.horizontalOffset", issues),
            ReadClamped(value, "gap", 0, 64, 8, $"{field}.gap", issues));
    }

    private static JsonObject WriteOverlay(OverlaySettings value, JsonObject? template)
    {
        JsonObject result = template?.DeepClone().AsObject() ?? new JsonObject();
        result["screenIdentifier"] = value.ScreenIdentifier;
        result["originX"] = value.OriginX;
        result["originY"] = value.OriginY;
        result["width"] = value.Width;
        result["clickThrough"] = value.ClickThrough;
        result["opacity"] = value.Opacity;
        result["pointerOverlapFadeEnabled"] = value.PointerOverlapFadeEnabled;
        result["pointerOverlapOpacity"] = value.PointerOverlapOpacity;
        result["pixelArtRendering"] = value.PixelArtRendering;
        JsonObject? storedBoundary = template?["movementBoundary"] as JsonObject;
        JsonObject boundary = storedBoundary is not null
            ? storedBoundary.DeepClone().AsObject()
            : new JsonObject();
        boundary["mode"] = BoundaryMode(value.MovementBoundary.Mode);
        boundary["screenIdentifier"] = value.MovementBoundary.ScreenIdentifier;
        if (value.MovementBoundary.NormalizedRect is { } rect)
        {
            JsonObject rectResult = storedBoundary?["normalizedRect"] is JsonObject storedRect
                ? storedRect.DeepClone().AsObject()
                : new JsonObject();
            rectResult["x"] = rect.X;
            rectResult["y"] = rect.Y;
            rectResult["width"] = rect.Width;
            rectResult["height"] = rect.Height;
            boundary["normalizedRect"] = rectResult;
        }
        else
        {
            boundary["normalizedRect"] = null;
        }
        result["movementBoundary"] = boundary;
        return result;
    }

    private static JsonObject WriteProfile(BehaviorProfile value, JsonObject? template)
    {
        JsonObject result = template?.DeepClone().AsObject() ?? new JsonObject();
        result["petKey"] = WritePetKey(value.PetKey, template?["petKey"] as JsonObject);
        result["mode"] = value.Mode == BehaviorMode.Automatic ? "automatic" : "manual";
        result["manualSequenceID"] = value.ManualSequenceId;
        var sequences = new JsonArray();
        foreach (BehaviorSequence sequence in value.Sequences)
        {
            JsonObject sequenceResult = FindObjectByStringId(template?["sequences"], sequence.Id)
                ?.DeepClone().AsObject() ?? new JsonObject();
            sequenceResult["id"] = sequence.Id;
            var steps = new JsonArray();
            for (int index = 0; index < sequence.Steps.Count; index++)
            {
                BehaviorStep step = sequence.Steps[index];
                JsonObject stepResult = template?["sequences"] is JsonArray storedSequences &&
                    FindObjectByStringId(storedSequences, sequence.Id)?["steps"] is JsonArray storedSteps &&
                    index < storedSteps.Count && storedSteps[index] is JsonObject storedStep
                        ? storedStep.DeepClone().AsObject()
                        : new JsonObject();
                stepResult["motionID"] = step.MotionId;
                stepResult["repeatCount"] = step.RepeatCount;
                stepResult.Remove("durationMilliseconds");
                stepResult.Remove("playbackSpeed");
                steps.Add(stepResult);
            }
            sequenceResult["steps"] = steps;
            sequenceResult["repeats"] = sequence.Repeats;
            sequences.Add(sequenceResult);
        }
        result["sequences"] = sequences;
        var rules = new JsonArray();
        foreach (AutomaticRule rule in value.AutomaticRules)
        {
            JsonObject ruleResult = FindObjectByGuidId(template?["automaticRules"], rule.Id)
                ?.DeepClone().AsObject() ?? new JsonObject();
            ruleResult["id"] = rule.Id.ToString("D");
            ruleResult["isEnabled"] = rule.IsEnabled;
            ruleResult["priority"] = rule.Priority;
            ruleResult["sequenceID"] = rule.SequenceId;
            ruleResult["condition"] = WriteCondition(
                rule.Condition,
                ruleResult["condition"] as JsonObject);
            rules.Add(ruleResult);
        }
        result["automaticRules"] = rules;
        result["movement"] = WriteMovement(value.Movement, template?["movement"] as JsonObject);
        result["pettingMotionID"] = value.PettingMotionId;
        result["speech"] = WriteSpeech(value.Speech, template?["speech"] as JsonObject);
        return result;
    }

    private static JsonObject WriteMovement(PetMovementSettings value, JsonObject? template)
    {
        JsonObject result = template?.DeepClone().AsObject() ?? new JsonObject();
        result["mode"] = value.Mode switch
        {
            PetMovementMode.Fixed => "fixed",
            PetMovementMode.CursorFollowing => "cursorFollowing",
            PetMovementMode.FreeRoaming => "freeRoaming",
            _ => "cursorAvoiding",
        };
        result["speed"] = value.Speed;
        result["cursorDistance"] = value.CursorDistance;
        result["stopRadius"] = value.StopRadius;
        result["freeRoamingDwellMilliseconds"] = value.FreeRoamingDwellMilliseconds;
        result["prefersFrontmostWindow"] = value.PrefersFrontmostWindow;
        result["cursorFollowingAnimation"] = WriteAnimation(value.CursorFollowingAnimation, template?["cursorFollowingAnimation"] as JsonObject);
        result["freeRoamingAnimation"] = WriteAnimation(value.FreeRoamingAnimation, template?["freeRoamingAnimation"] as JsonObject);
        result["cursorAvoidingIdleBehavior"] = value.CursorAvoidingIdleBehavior == CursorAvoidingIdleBehavior.Stationary
            ? "stationary"
            : "freeRoaming";
        result["cursorAvoidingDetectionDistance"] = value.CursorAvoidingDetectionDistance;
        result["cursorAvoidingSpeed"] = value.CursorAvoidingSpeed;
        result["cursorAvoidingAnimation"] = WriteAnimation(value.CursorAvoidingAnimation, template?["cursorAvoidingAnimation"] as JsonObject);
        return result;
    }

    private static JsonObject WriteAnimation(MovementAnimationSettings value, JsonObject? template)
    {
        JsonObject result = template?.DeepClone().AsObject() ?? new JsonObject();
        result["fallbackMotionID"] = value.FallbackMotionId;
        result["usesDirectionalMotions"] = value.UsesDirectionalMotions;
        result["usesDiagonalMotions"] = value.UsesDiagonalMotions;
        JsonObject directions = template?["directionMotionIDs"] is JsonObject storedDirections
            ? storedDirections.DeepClone().AsObject()
            : new JsonObject();
        directions["left"] = value.DirectionMotionIds.Left;
        directions["right"] = value.DirectionMotionIds.Right;
        directions["up"] = value.DirectionMotionIds.Up;
        directions["down"] = value.DirectionMotionIds.Down;
        directions["upLeft"] = value.DirectionMotionIds.UpLeft;
        directions["upRight"] = value.DirectionMotionIds.UpRight;
        directions["downLeft"] = value.DirectionMotionIds.DownLeft;
        directions["downRight"] = value.DirectionMotionIds.DownRight;
        result["directionMotionIDs"] = directions;
        return result;
    }

    private static JsonObject WriteSpeech(PetSpeechSettings value, JsonObject? template)
    {
        JsonObject result = template?.DeepClone().AsObject() ?? new JsonObject();
        result["isEnabled"] = value.IsEnabled;
        result["periodicIsEnabled"] = value.PeriodicIsEnabled;
        result["periodicIntervalMilliseconds"] = value.PeriodicIntervalMilliseconds;
        result["periodicOrder"] = value.PeriodicOrder == PetSpeechPeriodicOrder.Random ? "random" : "sequential";
        result["behaviorChangePolicy"] = value.BehaviorChangePolicy == PetSpeechBehaviorChangePolicy.Dismiss ? "dismiss" : "keep";
        var phrases = new JsonArray();
        foreach (PetSpeechPhrase phrase in value.Phrases)
        {
            JsonObject phraseResult = FindObjectByGuidId(template?["phrases"], phrase.Id)
                ?.DeepClone().AsObject() ?? new JsonObject();
            phraseResult["id"] = phrase.Id.ToString("D");
            phraseResult["text"] = phrase.Text;
            phraseResult["displayDurationMilliseconds"] = phrase.DisplayDurationMilliseconds;
            phraseResult["displayMode"] = phrase.DisplayMode == PetSpeechDisplayMode.Timed ? "timed" : "untilNextPhrase";
            phraseResult["trigger"] = WriteTrigger(
                phrase.Trigger,
                phraseResult["trigger"] as JsonObject);
            phrases.Add(phraseResult);
        }
        result["phrases"] = phrases;
        result["theme"] = WriteTheme(value.Theme, template?["theme"] as JsonObject);
        result["placement"] = WritePlacement(value.Placement, template?["placement"] as JsonObject);
        return result;
    }

    private static JsonObject WriteTheme(PetSpeechBubbleTheme value, JsonObject? template)
    {
        JsonObject result = template?.DeepClone().AsObject() ?? new JsonObject();
        result["colorStyle"] = value.ColorStyle.ToString().ToLowerInvariant();
        result["customBackgroundColor"] = WriteColor(
            value.CustomBackgroundColor,
            template?["customBackgroundColor"] as JsonObject);
        result["customTextColor"] = WriteColor(
            value.CustomTextColor,
            template?["customTextColor"] as JsonObject);
        result["backgroundOpacity"] = value.BackgroundOpacity;
        result["fontSize"] = value.FontSize;
        result["contentPadding"] = value.ContentPadding;
        result["cornerRadius"] = value.CornerRadius;
        result["showsTail"] = value.ShowsTail;
        result["tailAlignment"] = value.TailAlignment.ToString().ToLowerInvariant();
        return result;
    }

    private static JsonObject WritePlacement(PetSpeechBubblePlacementSettings value, JsonObject? template)
    {
        JsonObject result = template?.DeepClone().AsObject() ?? new JsonObject();
        result["preferredPosition"] = value.PreferredPosition.ToString().ToLowerInvariant();
        result["horizontalOffset"] = value.HorizontalOffset;
        result["gap"] = value.Gap;
        return result;
    }

    private static JsonObject WriteColor(PetSpeechColor value, JsonObject? template)
    {
        JsonObject result = template?.DeepClone().AsObject() ?? new JsonObject();
        result["red"] = value.Red;
        result["green"] = value.Green;
        result["blue"] = value.Blue;
        return result;
    }

    private static JsonObject WritePetKey(PetBehaviorKey key, JsonObject? template)
    {
        JsonObject result = template?.DeepClone().AsObject() ?? new JsonObject();
        switch (key)
        {
            case PetBehaviorKey.BuiltIn:
                result["type"] = "builtIn";
                result.Remove("installationID");
                break;
            case PetBehaviorKey.Installed installed:
                result["type"] = "installed";
                result["installationID"] = installed.InstallationId.ToString("D");
                break;
            default:
                throw InvalidSettings("behaviorProfiles.petKey");
        }
        return result;
    }

    private static JsonObject WriteCondition(RuleCondition condition, JsonObject? template)
    {
        JsonObject result = template?.DeepClone().AsObject() ?? new JsonObject();
        switch (condition)
        {
            case RuleCondition.Application application:
                result["type"] = "application";
                result["bundleIdentifier"] = application.ApplicationId;
                result.Remove("milliseconds");
                break;
            case RuleCondition.IdleAtLeast idle:
                result["type"] = "idleAtLeast";
                result["milliseconds"] = idle.Milliseconds;
                result.Remove("bundleIdentifier");
                break;
            case RuleCondition.Unsupported unsupported:
                result["type"] = unsupported.Type;
                result.Remove("bundleIdentifier");
                result.Remove("milliseconds");
                break;
            default:
                throw InvalidSettings("automaticRules.condition");
        }
        return result;
    }

    private static JsonObject WriteTrigger(PetSpeechTrigger trigger, JsonObject? template)
    {
        JsonObject result = template?.DeepClone().AsObject() ?? new JsonObject();
        switch (trigger)
        {
            case PetSpeechTrigger.Periodic:
                result["type"] = "periodic";
                result["sequenceID"] = null;
                break;
            case PetSpeechTrigger.Sequence sequence:
                result["type"] = "sequence";
                result["sequenceID"] = sequence.SequenceId;
                break;
            default:
                throw InvalidSettings("speech.phrases.trigger");
        }
        return result;
    }

    private static void Validate(AppSettings settings)
    {
        if (settings.LastUserPresentation is not (PetPresentation.Awake or PetPresentation.TuckedAway))
        {
            throw InvalidSettings("lastUserPresentation");
        }
        ValidateOverlay(settings.Overlay);
        if (settings.BehaviorProfiles.Count > AppSettingsLimits.MaximumBehaviorProfiles)
        {
            throw InvalidSettings("behaviorProfiles");
        }
        var keys = new HashSet<PetBehaviorKey>();
        for (int index = 0; index < settings.BehaviorProfiles.Count; index++)
        {
            BehaviorProfile profile = settings.BehaviorProfiles[index];
            string field = $"behaviorProfiles.{index}";
            if (!keys.Add(profile.PetKey))
            {
                throw InvalidSettings($"{field}.petKey");
            }
            ValidateProfile(profile, field);
        }
    }

    private static void ValidateOverlay(OverlaySettings value)
    {
        if (!ValidOptionalIdentifier(value.ScreenIdentifier) ||
            !double.IsFinite(value.OriginX) || !double.IsFinite(value.OriginY) ||
            !InRange(value.Width, 96, 384) || !InRange(value.Opacity, 0.1, 1) ||
            !InRange(value.PointerOverlapOpacity, 0.05, 1) ||
            !ValidBoundary(value.MovementBoundary))
        {
            throw InvalidSettings("overlay");
        }
    }

    private static void ValidateProfile(BehaviorProfile value, string field)
    {
        if (!Enum.IsDefined(value.Mode) ||
            value.Sequences.Count > 100 || value.AutomaticRules.Count > 100)
        {
            throw InvalidSettings(field);
        }
        var sequenceIds = new HashSet<string>(StringComparer.Ordinal);
        foreach (BehaviorSequence sequence in value.Sequences)
        {
            if (!ValidIdentifier(sequence.Id) || !sequenceIds.Add(sequence.Id) ||
                sequence.Steps.Count is < 1 or > 100 ||
                sequence.Steps.Any(step =>
                    !ValidIdentifier(step.MotionId) ||
                    step.RepeatCount is < 1 or > AppSettingsLimits.MaximumRepeatCount))
            {
                throw InvalidSettings($"{field}.sequences");
            }
        }
        if (value.ManualSequenceId is not null && !sequenceIds.Contains(value.ManualSequenceId))
        {
            throw InvalidSettings($"{field}.manualSequenceID");
        }
        var ruleIds = new HashSet<Guid>();
        foreach (AutomaticRule rule in value.AutomaticRules)
        {
            if (!ruleIds.Add(rule.Id) || !ValidIdentifier(rule.SequenceId) ||
                (rule.IsEnabled && !sequenceIds.Contains(rule.SequenceId)) ||
                !ValidCondition(rule.Condition, rule.IsEnabled))
            {
                throw InvalidSettings($"{field}.automaticRules");
            }
        }
        if (!ValidMovement(value.Movement) || !ValidOptionalIdentifier(value.PettingMotionId))
        {
            throw InvalidSettings($"{field}.movement");
        }
        ValidateSpeech(value.Speech, sequenceIds, $"{field}.speech");
    }

    private static void ValidateSpeech(PetSpeechSettings value, ISet<string> sequenceIds, string field)
    {
        if (!Enum.IsDefined(value.PeriodicOrder) ||
            !Enum.IsDefined(value.BehaviorChangePolicy) ||
            value.Phrases.Count > 100 ||
            value.PeriodicIntervalMilliseconds is < 5_000 or > 3_600_000 ||
            !ValidTheme(value.Theme) || !ValidPlacement(value.Placement))
        {
            throw InvalidSettings(field);
        }
        var ids = new HashSet<Guid>();
        foreach (PetSpeechPhrase phrase in value.Phrases)
        {
            bool validTrigger = phrase.Trigger switch
            {
                PetSpeechTrigger.Periodic => true,
                PetSpeechTrigger.Sequence sequence =>
                    ValidIdentifier(sequence.SequenceId) && sequenceIds.Contains(sequence.SequenceId),
                _ => false,
            };
            if (!ids.Add(phrase.Id) || string.IsNullOrWhiteSpace(phrase.Text) ||
                phrase.Text.Trim() != phrase.Text ||
                AppSettingsLimits.TextLength(phrase.Text) > 120 ||
                phrase.DisplayDurationMilliseconds is < 1_000 or > 30_000 ||
                !Enum.IsDefined(phrase.DisplayMode) ||
                !validTrigger)
            {
                throw InvalidSettings($"{field}.phrases");
            }
        }
    }

    private static bool ValidMovement(PetMovementSettings value) =>
        Enum.IsDefined(value.Mode) && Enum.IsDefined(value.CursorAvoidingIdleBehavior) &&
        InRange(value.Speed, 20, 1_000) && InRange(value.CursorDistance, 0, 512) &&
        InRange(value.StopRadius, 0, 128) &&
        value.FreeRoamingDwellMilliseconds is >= 500 and <= 300_000 &&
        InRange(value.CursorAvoidingDetectionDistance, 32, 1_024) &&
        InRange(value.CursorAvoidingSpeed, 20, 1_000) &&
        ValidAnimation(value.CursorFollowingAnimation) &&
        ValidAnimation(value.FreeRoamingAnimation) &&
        ValidAnimation(value.CursorAvoidingAnimation);

    private static bool ValidAnimation(MovementAnimationSettings value) =>
        (!value.UsesDiagonalMotions || value.UsesDirectionalMotions) &&
        ValidOptionalIdentifier(value.FallbackMotionId) &&
        value.DirectionMotionIds.All.All(ValidOptionalIdentifier);

    private static bool ValidTheme(PetSpeechBubbleTheme value) =>
        Enum.IsDefined(value.ColorStyle) && Enum.IsDefined(value.TailAlignment) &&
        value.CustomBackgroundColor.IsValid && value.CustomTextColor.IsValid &&
        InRange(value.BackgroundOpacity, 0.65, 1) && InRange(value.FontSize, 11, 24) &&
        InRange(value.ContentPadding, 6, 24) && InRange(value.CornerRadius, 0, 28) &&
        (value.ColorStyle != PetSpeechBubbleColorStyle.Custom ||
            value.CustomBackgroundColor.ContrastRatio(value.CustomTextColor) >= 4.5);

    private static bool ValidPlacement(PetSpeechBubblePlacementSettings value) =>
        Enum.IsDefined(value.PreferredPosition) &&
        InRange(value.HorizontalOffset, -160, 160) && InRange(value.Gap, 0, 64);

    private static bool ValidBoundary(MovementBoundarySettings value)
    {
        if (!Enum.IsDefined(value.Mode))
        {
            return false;
        }
        bool screenValid = ValidIdentifier(value.ScreenIdentifier);
        bool rectValid = value.NormalizedRect?.IsValid == true;
        return value.Mode switch
        {
            MovementBoundaryMode.AllDisplays =>
                (value.ScreenIdentifier is null || screenValid) &&
                (value.NormalizedRect is null || rectValid),
            MovementBoundaryMode.SelectedDisplay =>
                screenValid && (value.NormalizedRect is null || rectValid),
            MovementBoundaryMode.CustomArea => screenValid && rectValid,
            _ => false,
        };
    }

    private static bool ValidCondition(RuleCondition condition, bool enabled) => condition switch
    {
        RuleCondition.Application application => !enabled || ValidIdentifier(application.ApplicationId),
        RuleCondition.IdleAtLeast idle => !enabled || idle.Milliseconds is >= 1 and <= 86_400_000,
        RuleCondition.Unsupported unsupported => !enabled && ValidIdentifier(unsupported.Type),
        _ => false,
    };

    private static JsonObject? FindProfileTemplate(JsonObject? template, PetBehaviorKey key)
    {
        if (template?["behaviorProfiles"] is not JsonArray profiles)
        {
            return null;
        }
        return profiles.OfType<JsonObject>().FirstOrDefault(profile =>
            TryReadPetKey(profile["petKey"], out PetBehaviorKey candidate) && candidate == key);
    }

    private static JsonObject? FindObjectByStringId(JsonNode? node, string id) =>
        node is JsonArray values
            ? values.OfType<JsonObject>().FirstOrDefault(value =>
                TryString(value["id"], out string candidate) && candidate == id)
            : null;

    private static JsonObject? FindObjectByGuidId(JsonNode? node, Guid id) =>
        node is JsonArray values
            ? values.OfType<JsonObject>().FirstOrDefault(value =>
                TryGuid(value["id"], out Guid candidate) && candidate == id)
            : null;

    private static bool TryReadPetKey(JsonNode? node, out PetBehaviorKey key)
    {
        key = PetBehaviorKey.BuiltInKey;
        if (node is not JsonObject value || !TryString(value["type"], out string type))
        {
            return false;
        }
        if (string.Equals(type, "builtIn", StringComparison.Ordinal))
        {
            key = PetBehaviorKey.BuiltInKey;
            return true;
        }
        if (string.Equals(type, "installed", StringComparison.Ordinal) &&
            TryGuid(value["installationID"], out Guid installationId))
        {
            key = new PetBehaviorKey.Installed(installationId);
            return true;
        }
        return false;
    }

    private static Guid? ReadOptionalGuid(
        JsonObject value,
        string property,
        string field,
        List<SettingsRecoveryIssue> issues)
    {
        JsonNode? node = value[property];
        if (node is null)
        {
            return null;
        }
        if (TryGuid(node, out Guid id))
        {
            return id;
        }
        Invalid(field, issues);
        return null;
    }

    private static string? ReadOptionalIdentifier(
        JsonObject value,
        string property,
        string field,
        List<SettingsRecoveryIssue> issues,
        bool requireUnmodified)
    {
        JsonNode? node = value[property];
        if (node is null)
        {
            return null;
        }
        if (!TryString(node, out string text))
        {
            Invalid(field, issues);
            return null;
        }
        string trimmed = text.Trim();
        if (trimmed.Length == 0 || (requireUnmodified && trimmed != text))
        {
            Invalid(field, issues);
            return null;
        }
        if (trimmed != text)
        {
            Invalid(field, issues);
        }
        return trimmed;
    }

    private static T ReadEnum<T>(
        JsonObject value,
        string property,
        IReadOnlyDictionary<string, T> values,
        T fallback,
        string field,
        List<SettingsRecoveryIssue> issues) where T : struct
    {
        JsonNode? node = value[property];
        if (node is null)
        {
            return fallback;
        }
        if (TryString(node, out string text) && values.TryGetValue(text, out T result))
        {
            return result;
        }
        Invalid(field, issues);
        return fallback;
    }

    private static T? ReadOptionalEnum<T>(
        JsonObject value,
        string property,
        IReadOnlyDictionary<string, T> values,
        string field,
        List<SettingsRecoveryIssue> issues) where T : struct
    {
        JsonNode? node = value[property];
        if (TryString(node, out string text) && values.TryGetValue(text, out T result))
        {
            return result;
        }
        if (node is not null)
        {
            Invalid(field, issues);
        }
        return null;
    }

    private static bool ReadBool(JsonObject value, string property, bool fallback, string field, List<SettingsRecoveryIssue> issues)
    {
        JsonNode? node = value[property];
        if (node is null)
        {
            return fallback;
        }
        if (node is JsonValue json && json.TryGetValue(out bool result))
        {
            return result;
        }
        Invalid(field, issues);
        return fallback;
    }

    private static int ReadInt(JsonObject value, string property, int fallback, string field, List<SettingsRecoveryIssue> issues)
    {
        JsonNode? node = value[property];
        if (node is null)
        {
            return fallback;
        }
        if (TryInt(node, out int result))
        {
            return result;
        }
        Invalid(field, issues);
        return fallback;
    }

    private static long ReadLong(JsonObject value, string property, long fallback, string field, List<SettingsRecoveryIssue> issues)
    {
        JsonNode? node = value[property];
        if (node is null)
        {
            return fallback;
        }
        if (TryLong(node, out long result))
        {
            return result;
        }
        Invalid(field, issues);
        return fallback;
    }

    private static double ReadFinite(JsonObject value, string property, double fallback, string field, List<SettingsRecoveryIssue> issues)
    {
        JsonNode? node = value[property];
        if (node is null)
        {
            return fallback;
        }
        if (TryDouble(node, out double result) && double.IsFinite(result))
        {
            return result;
        }
        Invalid(field, issues);
        return fallback;
    }

    private static double ReadRanged(JsonObject value, string property, double minimum, double maximum, double fallback, string field, List<SettingsRecoveryIssue> issues)
    {
        JsonNode? node = value[property];
        if (node is null)
        {
            return fallback;
        }
        if (TryDouble(node, out double result) && InRange(result, minimum, maximum))
        {
            return result;
        }
        Invalid(field, issues);
        return fallback;
    }

    private static long ReadRangedLong(JsonObject value, string property, long minimum, long maximum, long fallback, string field, List<SettingsRecoveryIssue> issues)
    {
        JsonNode? node = value[property];
        if (node is null)
        {
            return fallback;
        }
        if (TryLong(node, out long result) && result >= minimum && result <= maximum)
        {
            return result;
        }
        Invalid(field, issues);
        return fallback;
    }

    private static double ReadClamped(JsonObject value, string property, double minimum, double maximum, double fallback, string field, List<SettingsRecoveryIssue> issues)
    {
        JsonNode? node = value[property];
        if (node is null)
        {
            return fallback;
        }
        if (!TryDouble(node, out double result) || !double.IsFinite(result))
        {
            Invalid(field, issues);
            return fallback;
        }
        double clamped = Math.Clamp(result, minimum, maximum);
        if (clamped != result)
        {
            Invalid(field, issues);
        }
        return clamped;
    }

    private static bool TryNormalizedIdentifier(JsonNode? node, out string value)
    {
        value = string.Empty;
        if (!TryString(node, out string text))
        {
            return false;
        }
        string trimmed = text.Trim();
        if (trimmed.Length == 0)
        {
            return false;
        }
        value = trimmed;
        return true;
    }

    private static bool TryString(JsonNode? node, out string value)
    {
        value = string.Empty;
        if (node is JsonValue json &&
            json.TryGetValue(out string? candidate) &&
            candidate is not null)
        {
            value = candidate;
            return true;
        }
        return false;
    }

    private static bool TryGuid(JsonNode? node, out Guid value)
    {
        value = default;
        return TryString(node, out string text) && Guid.TryParse(text, out value);
    }

    private static bool TryInt(JsonNode? node, out int value)
    {
        value = default;
        return node is JsonValue json && json.TryGetValue(out value);
    }

    private static bool TryLong(JsonNode? node, out long value)
    {
        value = default;
        return node is JsonValue json && json.TryGetValue(out value);
    }

    private static bool TryDouble(JsonNode? node, out double value)
    {
        value = default;
        return node is JsonValue json && json.TryGetValue(out value);
    }

    private static bool ValidIdentifier(string? value) =>
        value is not null && value.Length > 0 && value.Trim() == value;

    private static bool ValidOptionalIdentifier(string? value) =>
        value is null || ValidIdentifier(value);

    private static bool InRange(double value, double minimum, double maximum) =>
        double.IsFinite(value) && value >= minimum && value <= maximum;

    private static string BoundaryMode(MovementBoundaryMode mode) => mode switch
    {
        MovementBoundaryMode.AllDisplays => "allDisplays",
        MovementBoundaryMode.SelectedDisplay => "selectedDisplay",
        _ => "customArea",
    };

    private static string ReadDisplayValue(JsonNode? node) =>
        TryString(node, out string value) ? value : "unknown";

    private static void Invalid(string field, List<SettingsRecoveryIssue> issues) =>
        issues.Add(new SettingsRecoveryIssue(SettingsRecoveryKind.InvalidField, field));

    private static void Truncated(string field, List<SettingsRecoveryIssue> issues) =>
        issues.Add(new SettingsRecoveryIssue(SettingsRecoveryKind.TruncatedCollection, field));

    private static AppSettingsException InvalidSettings(string field) =>
        new(AppSettingsError.InvalidSettings, $"저장할 설정 값이 올바르지 않습니다: {field}");
}
