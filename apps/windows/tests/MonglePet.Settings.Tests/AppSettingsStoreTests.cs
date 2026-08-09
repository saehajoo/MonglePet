using System.Text;
using System.Text.Json.Nodes;
using MonglePet.Core.Behavior;

namespace MonglePet.Settings.Tests;

public sealed class AppSettingsStoreTests
{
    [Fact]
    public void BuildsSettingsPathFromInjectedApplicationLocalDataRoot()
    {
        string root = Path.Combine("C:\\", "PackageLocalState");

        string path = AppSettingsPaths.FromAppLocalDataRoot(root);

        Assert.Equal(Path.Combine(root, "MonglePet", "settings.json"), path);
    }

    [Fact]
    public void MissingFileUsesDefaultsThenWritesCompleteSchemaV10Document()
    {
        using var workspace = new TemporaryDirectory();
        Guid selectedId = Guid.Parse("10000000-0000-0000-0000-000000000001");
        var store = workspace.CreateStore();

        AppSettingsLoadResult initial = store.Load();
        store.SaveSelectedPetInstallationId(selectedId);
        AppSettingsLoadResult reloaded = workspace.CreateStore().Load();
        JsonObject document = ReadDocument(workspace.SettingsPath);

        Assert.Equal(AppSettingsLoadSource.Defaults, initial.Source);
        Assert.Null(initial.SelectedPetInstallationId);
        Assert.Equal(selectedId, reloaded.SelectedPetInstallationId);
        Assert.Equal(10, document["schemaVersion"]!.GetValue<int>());
        Assert.Equal("awake", document["lastUserPresentation"]!.GetValue<string>());
        Assert.NotNull(document["overlay"]?["movementBoundary"]);
        Assert.NotNull(document["behaviorProfiles"]?[0]?["movement"]);
        Assert.Empty(Directory.EnumerateFiles(workspace.Path, ".settings-*.tmp"));
    }

    [Fact]
    public void DisplaySettingsAndUserPresentationRoundTripAsTypedValues()
    {
        using var workspace = new TemporaryDirectory();
        var store = workspace.CreateStore();
        AppSettings settings = store.Load().Settings!;
        AppSettings updated = settings with
        {
            LastUserPresentation = PetPresentation.TuckedAway,
            Overlay = settings.Overlay with
            {
                Width = 304,
                ClickThrough = true,
                Opacity = 0.65,
                PixelArtRendering = true,
            },
        };

        store.Save(updated);
        AppSettings reloaded = workspace.CreateStore().Load().Settings!;

        Assert.Equal(PetPresentation.TuckedAway, reloaded.LastUserPresentation);
        Assert.Equal(304, reloaded.Overlay.Width);
        Assert.True(reloaded.Overlay.ClickThrough);
        Assert.Equal(0.65, reloaded.Overlay.Opacity);
        Assert.True(reloaded.Overlay.PixelArtRendering);
        Assert.Empty(Directory.EnumerateFiles(workspace.Path, ".settings-*.tmp"));
    }

    [Fact]
    public void BehaviorProfileDefaultsUsePetKeyAndCurrentDefaultRepeatingSequence()
    {
        Guid installationId = Guid.Parse("11000000-0000-0000-0000-000000000001");
        PetBehaviorKey key = BehaviorProfileDefaults.KeyForInstallation(installationId);

        BehaviorProfile profile = BehaviorProfileDefaults.Create(key);
        BehaviorSequence sequence = Assert.Single(profile.Sequences);
        BehaviorStep step = Assert.Single(sequence.Steps);

        Assert.Equal(new PetBehaviorKey.Installed(installationId), profile.PetKey);
        Assert.Equal(BehaviorMode.Automatic, profile.Mode);
        Assert.Equal(BehaviorMotionReferences.DefaultSequence, profile.ManualSequenceId);
        Assert.Equal(BehaviorMotionReferences.DefaultSequence, sequence.Id);
        Assert.True(sequence.Repeats);
        Assert.Equal(BehaviorMotionReferences.CurrentPetDefault, step.MotionId);
        Assert.Equal(1, step.RepeatCount);
        Assert.Empty(profile.AutomaticRules);
    }

    [Fact]
    public void UpdatingSelectionPreservesUnusedSchemaV10Fields()
    {
        using var workspace = new TemporaryDirectory();
        Guid selectedId = Guid.Parse("20000000-0000-0000-0000-000000000001");
        File.WriteAllText(
            workspace.SettingsPath,
            """
            {
              "schemaVersion": 10,
              "selectedPetInstallationID": null,
              "lastUserPresentation": "tuckedAway",
              "overlay": { "width": 321, "windowsOnlyMarker": "keep" },
              "behaviorProfiles": [],
              "unrecognizedCurrentField": { "nested": true }
            }
            """);
        var store = workspace.CreateStore();

        store.Load();
        store.SaveSelectedPetInstallationId(selectedId);
        JsonObject saved = ReadDocument(workspace.SettingsPath);

        Assert.Equal(selectedId.ToString("D"), saved["selectedPetInstallationID"]!.GetValue<string>());
        Assert.Equal("tuckedAway", saved["lastUserPresentation"]!.GetValue<string>());
        Assert.Equal(321, saved["overlay"]?["width"]?.GetValue<int>());
        Assert.Equal("keep", saved["overlay"]?["windowsOnlyMarker"]?.GetValue<string>());
        Assert.True(saved["unrecognizedCurrentField"]?["nested"]?.GetValue<bool>());
    }

    [Fact]
    public void InvalidSelectedUuidRecoversOnlyThatField()
    {
        using var workspace = new TemporaryDirectory();
        File.WriteAllText(
            workspace.SettingsPath,
            """
            {
              "schemaVersion": 10,
              "selectedPetInstallationID": "not-a-uuid",
              "lastUserPresentation": "awake",
              "overlay": { "width": 222 },
              "behaviorProfiles": []
            }
            """);
        var store = workspace.CreateStore();

        AppSettingsLoadResult loaded = store.Load();
        store.SaveSelectedPetInstallationId(null);
        JsonObject saved = ReadDocument(workspace.SettingsPath);

        Assert.Equal(AppSettingsLoadSource.Recovered, loaded.Source);
        Assert.Null(loaded.SelectedPetInstallationId);
        Assert.Single(loaded.Issues);
        Assert.Equal(222, saved["overlay"]?["width"]?.GetValue<int>());
        Assert.Null(saved["selectedPetInstallationID"]);
    }

    [Fact]
    public void CorruptFileIsQuarantinedBeforeDefaultsCanBeSaved()
    {
        using var workspace = new TemporaryDirectory();
        Guid quarantineId = Guid.Parse("30000000-0000-0000-0000-000000000001");
        File.WriteAllText(workspace.SettingsPath, "{not-json");
        var store = workspace.CreateStore(quarantineId: quarantineId);

        AppSettingsLoadResult loaded = store.Load();

        string quarantinePath = Path.Combine(
            workspace.Path,
            $"settings.corrupt-{quarantineId:D}.json");
        Assert.Equal(AppSettingsLoadSource.Recovered, loaded.Source);
        Assert.True(loaded.IsWritingEnabled);
        Assert.False(File.Exists(workspace.SettingsPath));
        Assert.Equal("{not-json", File.ReadAllText(quarantinePath));

        store.SaveSelectedPetInstallationId(null);
        Assert.True(File.Exists(workspace.SettingsPath));
        Assert.True(File.Exists(quarantinePath));
    }

    [Fact]
    public void OversizedFileIsQuarantinedWithoutJsonDecoding()
    {
        using var workspace = new TemporaryDirectory();
        Guid quarantineId = Guid.Parse("40000000-0000-0000-0000-000000000001");
        File.WriteAllBytes(
            workspace.SettingsPath,
            Enumerable.Repeat((byte)' ', AppSettingsStore.MaximumFileSize + 1).ToArray());

        AppSettingsLoadResult loaded = workspace.CreateStore(quarantineId: quarantineId).Load();

        string quarantinePath = Path.Combine(
            workspace.Path,
            $"settings.corrupt-{quarantineId:D}.json");
        Assert.Equal(AppSettingsLoadSource.Recovered, loaded.Source);
        Assert.Equal(AppSettingsStore.MaximumFileSize + 1, new FileInfo(quarantinePath).Length);
    }

    [Fact]
    public void NewerSchemaIsPreservedAndDisablesWriting()
    {
        using var workspace = new TemporaryDirectory();
        byte[] original = Encoding.UTF8.GetBytes(
            "{\"schemaVersion\":11,\"futureValue\":true}");
        File.WriteAllBytes(workspace.SettingsPath, original);
        var store = workspace.CreateStore();

        AppSettingsLoadResult loaded = store.Load();
        AppSettingsException exception = Assert.Throws<AppSettingsException>(
            () => store.SaveSelectedPetInstallationId(Guid.NewGuid()));

        Assert.Equal(AppSettingsLoadSource.NewerSchema, loaded.Source);
        Assert.Equal(11, loaded.PreservedSchemaVersion);
        Assert.False(loaded.IsWritingEnabled);
        Assert.Equal(AppSettingsError.WritingDisabled, exception.Error);
        Assert.Equal(original, File.ReadAllBytes(workspace.SettingsPath));
    }

    [Fact]
    public void V1FixtureMigratesMotionDurationsAndAllLaterSchemasToV10()
    {
        using var workspace = new TemporaryDirectory();
        File.Copy(
            Path.Combine(AppContext.BaseDirectory, "Fixtures", "settings-v1-migration.json"),
            workspace.SettingsPath);
        var store = workspace.CreateStore(cycleResolver: (_, motionId) => motionId switch
        {
            "focus" => 800,
            "__monglepet_current_pet_default__" => 600,
            _ => null,
        });

        AppSettingsLoadResult loaded = store.Load();
        JsonObject migrated = ReadDocument(workspace.SettingsPath);
        JsonObject profile = migrated["behaviorProfiles"]![0]!.AsObject();
        JsonArray steps = profile["sequences"]![0]!["steps"]!.AsArray();

        Assert.Equal(AppSettingsLoadSource.Migrated, loaded.Source);
        Assert.Equal(1, loaded.MigratedFromSchemaVersion);
        Assert.True(loaded.IsWritingEnabled);
        Assert.Equal(10, migrated["schemaVersion"]!.GetValue<int>());
        Assert.Equal("installed", profile["petKey"]?["type"]?.GetValue<string>());
        Assert.Equal(3, steps[0]?["repeatCount"]?.GetValue<int>());
        Assert.Equal(2, steps[1]?["repeatCount"]?.GetValue<int>());
        Assert.Equal(
            "__monglepet_current_pet_default__",
            steps[2]?["motionID"]?.GetValue<string>());
        Assert.Equal(1, steps[2]?["repeatCount"]?.GetValue<int>());
        Assert.Null(steps[0]?["durationMilliseconds"]);
        Assert.Equal("fixed", profile["movement"]?["mode"]?.GetValue<string>());
        Assert.Equal("automatic", profile["speech"]?["placement"]?["preferredPosition"]?.GetValue<string>());
        Assert.Empty(Directory.EnumerateFiles(workspace.Path, ".settings-*.tmp"));

        byte[] firstMigration = File.ReadAllBytes(workspace.SettingsPath);
        AppSettingsLoadResult reloaded = workspace.CreateStore().Load();
        Assert.Equal(AppSettingsLoadSource.File, reloaded.Source);
        Assert.Equal(firstMigration, File.ReadAllBytes(workspace.SettingsPath));
    }

    [Fact]
    public void V1WithoutSelectedPetDefinitionPreservesOriginalAndDisablesWriting()
    {
        using var workspace = new TemporaryDirectory();
        File.Copy(
            Path.Combine(AppContext.BaseDirectory, "Fixtures", "settings-v1-migration.json"),
            workspace.SettingsPath);
        byte[] original = File.ReadAllBytes(workspace.SettingsPath);
        var store = workspace.CreateStore();

        AppSettingsLoadResult loaded = store.Load();

        Assert.Equal(AppSettingsLoadSource.UnsupportedLegacySchema, loaded.Source);
        Assert.Equal(1, loaded.PreservedSchemaVersion);
        Assert.False(loaded.IsWritingEnabled);
        Assert.Equal(original, File.ReadAllBytes(workspace.SettingsPath));
        Assert.Equal(
            AppSettingsError.WritingDisabled,
            Assert.Throws<AppSettingsException>(
                () => store.SaveSelectedPetInstallationId(null)).Error);
    }

    [Theory]
    [InlineData(2)]
    [InlineData(3)]
    [InlineData(4)]
    [InlineData(5)]
    [InlineData(6)]
    [InlineData(7)]
    [InlineData(8)]
    [InlineData(9)]
    public void EachLegacyStartingSchemaMigratesSequentiallyAndPreservesValues(int schema)
    {
        using var workspace = new TemporaryDirectory();
        File.WriteAllText(workspace.SettingsPath, CreateLegacyDocument(schema).ToJsonString());

        AppSettingsLoadResult loaded = workspace.CreateStore().Load();
        JsonObject migrated = ReadDocument(workspace.SettingsPath);
        JsonObject overlay = migrated["overlay"]!.AsObject();
        JsonObject profile = migrated["behaviorProfiles"]![0]!.AsObject();
        JsonObject movement = profile["movement"]!.AsObject();
        JsonObject speech = profile["speech"]!.AsObject();

        Assert.Equal(AppSettingsLoadSource.Migrated, loaded.Source);
        Assert.Equal(schema, loaded.MigratedFromSchemaVersion);
        Assert.True(loaded.IsWritingEnabled);
        Assert.Equal(10, migrated["schemaVersion"]!.GetValue<int>());
        Assert.Equal("preserve", overlay["qaMarker"]!.GetValue<string>());
        Assert.Equal(schema >= 3 ? 240 : 160, movement["speed"]!.GetValue<int>());
        Assert.Equal(schema >= 3 ? "walk" : null, movement["freeRoamingAnimation"]?["fallbackMotionID"]?.GetValue<string>());
        Assert.Equal(schema >= 6 ? 444 : 320, movement["cursorAvoidingSpeed"]!.GetValue<int>());
        Assert.Equal(schema >= 7 ? 90_000 : 60_000, speech["periodicIntervalMilliseconds"]!.GetValue<int>());
        Assert.Equal(schema >= 8 ? "mint" : "system", speech["theme"]?["colorStyle"]?.GetValue<string>());
        Assert.Equal(schema >= 9 ? "sequential" : "random", speech["periodicOrder"]!.GetValue<string>());
        Assert.Equal("automatic", speech["placement"]?["preferredPosition"]?.GetValue<string>());
        Assert.Equal("keep-profile", profile["qaProfileMarker"]!.GetValue<string>());
        Assert.Empty(Directory.EnumerateFiles(workspace.Path, ".settings-*.tmp"));
    }

    [Fact]
    public void StructurallyInvalidLegacySchemaIsQuarantined()
    {
        using var workspace = new TemporaryDirectory();
        Guid quarantineId = Guid.Parse("50000000-0000-0000-0000-000000000002");
        File.WriteAllText(
            workspace.SettingsPath,
            "{\"schemaVersion\":5,\"selectedPetInstallationID\":null}");

        AppSettingsLoadResult loaded = workspace.CreateStore(
            quarantineId: quarantineId).Load();

        Assert.Equal(AppSettingsLoadSource.Recovered, loaded.Source);
        Assert.True(loaded.IsWritingEnabled);
        Assert.True(File.Exists(Path.Combine(
            workspace.Path,
            $"settings.corrupt-{quarantineId:D}.json")));
        Assert.False(File.Exists(workspace.SettingsPath));
    }

    [Fact]
    public void CompleteSchemaV10MapsAllDomainAreasAndPreservesExtensionsOnSave()
    {
        using var workspace = new TemporaryDirectory();
        JsonObject source = CreateSchemaV10Document();
        File.WriteAllText(workspace.SettingsPath, source.ToJsonString());
        var store = workspace.CreateStore();

        AppSettingsLoadResult loaded = store.Load();
        AppSettings settings = Assert.IsType<AppSettings>(loaded.Settings);
        BehaviorProfile profile = Assert.Single(settings.BehaviorProfiles);

        Assert.Equal(AppSettingsLoadSource.File, loaded.Source);
        Assert.Empty(Assert.IsAssignableFrom<IReadOnlyList<SettingsRecoveryIssue>>(loaded.RecoveryIssues));
        Assert.Equal(PetPresentation.TuckedAway, settings.LastUserPresentation);
        Assert.Equal(240, settings.Overlay.Width);
        Assert.Equal(MovementBoundaryMode.SelectedDisplay, settings.Overlay.MovementBoundary.Mode);
        Assert.Equal(BehaviorMode.Manual, profile.Mode);
        Assert.Equal(PetMovementMode.FreeRoaming, profile.Movement.Mode);
        Assert.True(profile.Movement.FreeRoamingAnimation.UsesDirectionalMotions);
        Assert.Equal("walk-left", profile.Movement.FreeRoamingAnimation.DirectionMotionIds.Left);
        Assert.Equal("happy", profile.PettingMotionId);
        Assert.Equal(PetSpeechPeriodicOrder.Sequential, profile.Speech.PeriodicOrder);
        Assert.Equal(PetSpeechBubbleColorStyle.Mint, profile.Speech.Theme.ColorStyle);
        Assert.Equal(PetSpeechBubblePreferredPosition.Above, profile.Speech.Placement.PreferredPosition);
        Assert.IsType<RuleCondition.IdleAtLeast>(Assert.Single(profile.AutomaticRules).Condition);
        Assert.IsType<PetSpeechTrigger.Sequence>(Assert.Single(profile.Speech.Phrases).Trigger);

        store.Save(settings with
        {
            Overlay = settings.Overlay with { Width = 260 },
        });
        JsonObject saved = ReadDocument(workspace.SettingsPath);

        Assert.Equal(260, saved["overlay"]?["width"]?.GetValue<double>());
        Assert.Equal("top", saved["extension"]?.GetValue<string>());
        Assert.Equal("overlay", saved["overlay"]?["extension"]?.GetValue<string>());
        Assert.Equal("profile", saved["behaviorProfiles"]?[0]?["extension"]?.GetValue<string>());
        Assert.Equal("sequence", saved["behaviorProfiles"]?[0]?["sequences"]?[0]?["extension"]?.GetValue<string>());
        Assert.Equal("rule", saved["behaviorProfiles"]?[0]?["automaticRules"]?[0]?["extension"]?.GetValue<string>());
        Assert.Equal("condition", saved["behaviorProfiles"]?[0]?["automaticRules"]?[0]?["condition"]?["extension"]?.GetValue<string>());
        Assert.Equal("phrase", saved["behaviorProfiles"]?[0]?["speech"]?["phrases"]?[0]?["extension"]?.GetValue<string>());
        Assert.Equal("trigger", saved["behaviorProfiles"]?[0]?["speech"]?["phrases"]?[0]?["trigger"]?["extension"]?.GetValue<string>());
        AppSettingsLoadResult reloaded = workspace.CreateStore().Load();
        Assert.Equal(AppSettingsLoadSource.File, reloaded.Source);
        Assert.Equal(260, reloaded.Settings!.Overlay.Width);
        Assert.Empty(Directory.EnumerateFiles(workspace.Path, ".settings-*.tmp"));
    }

    [Fact]
    public void CurrentSchemaRecoversInvalidItemsIndependentlyWithoutImmediateRewrite()
    {
        using var workspace = new TemporaryDirectory();
        JsonObject source = CreateSchemaV10Document();
        source["selectedPetInstallationID"] = "not-a-uuid";
        source["lastUserPresentation"] = "suspended";
        JsonObject overlay = source["overlay"]!.AsObject();
        overlay["width"] = 999;
        overlay["movementBoundary"] = new JsonObject
        {
            ["mode"] = "customArea",
            ["screenIdentifier"] = null,
            ["normalizedRect"] = new JsonObject
            {
                ["x"] = 0,
                ["y"] = 0,
                ["width"] = 1,
                ["height"] = 1,
            },
        };
        JsonObject profile = source["behaviorProfiles"]![0]!.AsObject();
        profile["mode"] = "unexpected";
        profile["manualSequenceID"] = "missing";
        profile["sequences"]![0]!["steps"]!.AsArray().Add(new JsonObject
        {
            ["motionID"] = " bad ",
            ["repeatCount"] = 0,
        });
        profile["automaticRules"]![0]!["sequenceID"] = "missing";
        profile["automaticRules"]!.AsArray().Add(new JsonObject
        {
            ["id"] = "invalid",
            ["sequenceID"] = "routine",
        });
        JsonObject movement = profile["movement"]!.AsObject();
        movement["speed"] = -1;
        JsonObject animation = movement["freeRoamingAnimation"]!.AsObject();
        animation["usesDirectionalMotions"] = false;
        animation["usesDiagonalMotions"] = true;
        animation["directionMotionIDs"]!["right"] = " invalid ";
        JsonObject speech = profile["speech"]!.AsObject();
        speech["periodicIntervalMilliseconds"] = 1;
        speech["phrases"]![0]!["displayMode"] = "forever";
        speech["phrases"]!.AsArray().Add(new JsonObject
        {
            ["id"] = "99999999-9999-9999-9999-999999999999",
            ["text"] = "invalid reference",
            ["displayDurationMilliseconds"] = 3000,
            ["displayMode"] = "timed",
            ["trigger"] = new JsonObject
            {
                ["type"] = "sequence",
                ["sequenceID"] = "missing",
            },
        });
        JsonObject theme = speech["theme"]!.AsObject();
        theme["colorStyle"] = "custom";
        theme["customBackgroundColor"] = new JsonObject { ["red"] = 1, ["green"] = 1, ["blue"] = 1 };
        theme["customTextColor"] = new JsonObject { ["red"] = 1, ["green"] = 1, ["blue"] = 1 };
        speech["placement"]!["horizontalOffset"] = 999;
        speech["placement"]!["gap"] = -20;
        profile.Parent!.AsArray().Add(profile.DeepClone());
        string original = source.ToJsonString();
        File.WriteAllText(workspace.SettingsPath, original);

        AppSettingsLoadResult loaded = workspace.CreateStore().Load();
        AppSettings settings = Assert.IsType<AppSettings>(loaded.Settings);
        BehaviorProfile recovered = Assert.Single(settings.BehaviorProfiles);

        Assert.Equal(AppSettingsLoadSource.Recovered, loaded.Source);
        Assert.Null(settings.SelectedPetInstallationId);
        Assert.Equal(PetPresentation.Awake, settings.LastUserPresentation);
        Assert.Equal(384, settings.Overlay.Width);
        Assert.Equal(MovementBoundaryMode.AllDisplays, settings.Overlay.MovementBoundary.Mode);
        Assert.Equal(BehaviorMode.Automatic, recovered.Mode);
        Assert.Null(recovered.ManualSequenceId);
        Assert.Single(Assert.Single(recovered.Sequences).Steps);
        Assert.False(Assert.Single(recovered.AutomaticRules).IsEnabled);
        Assert.Equal(160, recovered.Movement.Speed);
        Assert.False(recovered.Movement.FreeRoamingAnimation.UsesDiagonalMotions);
        Assert.Null(recovered.Movement.FreeRoamingAnimation.DirectionMotionIds.Right);
        Assert.Equal(60_000, recovered.Speech.PeriodicIntervalMilliseconds);
        Assert.Single(recovered.Speech.Phrases);
        Assert.Equal(PetSpeechDisplayMode.Timed, recovered.Speech.Phrases[0].DisplayMode);
        Assert.Equal(PetSpeechColor.Black, recovered.Speech.Theme.CustomTextColor);
        Assert.Equal(160, recovered.Speech.Placement.HorizontalOffset);
        Assert.Equal(0, recovered.Speech.Placement.Gap);
        Assert.Contains(loaded.RecoveryIssues!, issue => issue.Kind == SettingsRecoveryKind.DisabledRule);
        Assert.Contains(loaded.RecoveryIssues!, issue => issue.Kind == SettingsRecoveryKind.DroppedRule);
        Assert.Equal(original, File.ReadAllText(workspace.SettingsPath));
    }

    [Fact]
    public void CurrentSchemaTruncatesOversizedSequenceCollectionInStoredOrder()
    {
        using var workspace = new TemporaryDirectory();
        JsonObject source = CreateSchemaV10Document();
        JsonArray sequences = source["behaviorProfiles"]![0]!["sequences"]!.AsArray();
        sequences.Clear();
        for (int index = 0; index < AppSettingsLimits.MaximumSequences + 1; index++)
        {
            sequences.Add(new JsonObject
            {
                ["id"] = $"sequence-{index}",
                ["steps"] = new JsonArray(new JsonObject
                {
                    ["motionID"] = "idle",
                    ["repeatCount"] = 1,
                }),
                ["repeats"] = true,
            });
        }
        File.WriteAllText(workspace.SettingsPath, source.ToJsonString());

        AppSettingsLoadResult loaded = workspace.CreateStore().Load();
        IReadOnlyList<BehaviorSequence> mapped = Assert.Single(loaded.Settings!.BehaviorProfiles).Sequences;

        Assert.Equal(AppSettingsLimits.MaximumSequences, mapped.Count);
        Assert.Equal("sequence-0", mapped[0].Id);
        Assert.Equal("sequence-99", mapped[^1].Id);
        Assert.Contains(
            loaded.RecoveryIssues!,
            issue => issue == new SettingsRecoveryIssue(
                SettingsRecoveryKind.TruncatedCollection,
                "behaviorProfiles.0.sequences"));
    }

    [Fact]
    public void InvalidDomainSaveIsRejectedWithoutChangingExistingFile()
    {
        using var workspace = new TemporaryDirectory();
        File.WriteAllText(workspace.SettingsPath, CreateSchemaV10Document().ToJsonString());
        var store = workspace.CreateStore();
        AppSettings settings = store.Load().Settings!;
        byte[] original = File.ReadAllBytes(workspace.SettingsPath);

        AppSettingsException exception = Assert.Throws<AppSettingsException>(() =>
            store.Save(settings with
            {
                Overlay = settings.Overlay with { Width = double.NaN },
            }));

        Assert.Equal(AppSettingsError.InvalidSettings, exception.Error);
        Assert.Equal(original, File.ReadAllBytes(workspace.SettingsPath));
        Assert.Empty(Directory.EnumerateFiles(workspace.Path, ".settings-*.tmp"));
    }

    [Fact]
    public void ReplacingExistingSettingsIsAtomicAndCleansTemporaryFile()
    {
        using var workspace = new TemporaryDirectory();
        Guid temporaryId = Guid.Parse("60000000-0000-0000-0000-000000000001");
        var store = workspace.CreateStore(temporaryId: temporaryId);
        store.Load();
        store.SaveSelectedPetInstallationId(Guid.NewGuid());

        store.SaveSelectedPetInstallationId(null);

        Assert.Null(workspace.CreateStore().Load().SelectedPetInstallationId);
        Assert.Empty(Directory.EnumerateFiles(workspace.Path, ".settings-*.tmp"));
        Assert.Equal(
            "settings.json",
            Path.GetFileName(Assert.Single(Directory.EnumerateFiles(workspace.Path))));
    }

    private static JsonObject ReadDocument(string path) =>
        JsonNode.Parse(File.ReadAllText(path))!.AsObject();

    private static JsonObject CreateLegacyDocument(int schema)
    {
        var overlay = new JsonObject
        {
            ["screenIdentifier"] = "display-1",
            ["originX"] = 123,
            ["originY"] = 234,
            ["width"] = 240,
            ["clickThrough"] = true,
            ["qaMarker"] = "preserve",
        };
        if (schema >= 4)
        {
            overlay["opacity"] = 0.75;
            overlay["pointerOverlapFadeEnabled"] = true;
            overlay["pointerOverlapOpacity"] = 0.15;
            if (schema > 4)
            {
                overlay["pixelArtRendering"] = true;
            }
            overlay["movementBoundary"] = new JsonObject
            {
                ["mode"] = "allDisplays",
                ["screenIdentifier"] = null,
                ["normalizedRect"] = null,
            };
        }

        var profile = new JsonObject
        {
            ["petKey"] = new JsonObject { ["type"] = "builtIn" },
            ["mode"] = "manual",
            ["manualSequenceID"] = "routine",
            ["sequences"] = new JsonArray(new JsonObject
            {
                ["id"] = "routine",
                ["steps"] = new JsonArray(new JsonObject
                {
                    ["motionID"] = "idle",
                    ["repeatCount"] = 2,
                }),
                ["repeats"] = true,
            }),
            ["automaticRules"] = new JsonArray(),
            ["qaProfileMarker"] = "keep-profile",
        };

        if (schema >= 3)
        {
            var movement = new JsonObject
            {
                ["mode"] = "freeRoaming",
                ["speed"] = 240,
                ["cursorDistance"] = 120,
                ["stopRadius"] = 20,
                ["freeRoamingDwellMilliseconds"] = 9000,
                ["prefersFrontmostWindow"] = false,
            };
            if (schema < 5)
            {
                movement["cursorFollowingMotionID"] = "run";
                movement["freeRoamingMotionID"] = "walk";
            }
            else
            {
                movement["cursorFollowingAnimation"] = CreateAnimation("run");
                movement["freeRoamingAnimation"] = CreateAnimation("walk");
            }
            if (schema >= 6)
            {
                movement["cursorAvoidingIdleBehavior"] = "freeRoaming";
                movement["cursorAvoidingDetectionDistance"] = 222;
                movement["cursorAvoidingSpeed"] = 444;
                movement["cursorAvoidingAnimation"] = CreateAnimation("escape");
            }
            profile["movement"] = movement;
            profile["pettingMotionID"] = "happy";
        }

        if (schema >= 7)
        {
            var phrase = new JsonObject
            {
                ["id"] = "77777777-7777-7777-7777-777777777777",
                ["text"] = "hello",
                ["displayDurationMilliseconds"] = 3000,
                ["trigger"] = new JsonObject
                {
                    ["type"] = "periodic",
                    ["sequenceID"] = null,
                },
            };
            if (schema >= 9)
            {
                phrase["displayMode"] = "untilNextPhrase";
            }
            var speech = new JsonObject
            {
                ["isEnabled"] = true,
                ["periodicIntervalMilliseconds"] = 90_000,
                ["phrases"] = new JsonArray(phrase),
            };
            if (schema >= 8)
            {
                speech["theme"] = CreateTheme("mint");
            }
            if (schema >= 9)
            {
                speech["periodicIsEnabled"] = true;
                speech["periodicOrder"] = "sequential";
                speech["behaviorChangePolicy"] = "keep";
            }
            profile["speech"] = speech;
        }

        return new JsonObject
        {
            ["schemaVersion"] = schema,
            ["selectedPetInstallationID"] = null,
            ["lastUserPresentation"] = "tuckedAway",
            ["overlay"] = overlay,
            ["behaviorProfiles"] = new JsonArray(profile),
        };
    }

    private static JsonObject CreateSchemaV10Document()
    {
        JsonObject document = CreateLegacyDocument(9);
        document["schemaVersion"] = 10;
        document["extension"] = "top";
        JsonObject overlay = document["overlay"]!.AsObject();
        overlay["extension"] = "overlay";
        overlay["movementBoundary"] = new JsonObject
        {
            ["mode"] = "selectedDisplay",
            ["screenIdentifier"] = "display-1",
            ["normalizedRect"] = null,
        };
        JsonObject profile = document["behaviorProfiles"]![0]!.AsObject();
        profile["extension"] = "profile";
        profile["sequences"]![0]!["extension"] = "sequence";
        JsonObject freeRoaming = profile["movement"]!["freeRoamingAnimation"]!.AsObject();
        freeRoaming["usesDirectionalMotions"] = true;
        freeRoaming["directionMotionIDs"]!["left"] = "walk-left";
        freeRoaming["directionMotionIDs"]!["right"] = "walk-right";
        profile["automaticRules"] = new JsonArray(new JsonObject
        {
            ["id"] = "88888888-8888-8888-8888-888888888888",
            ["isEnabled"] = true,
            ["priority"] = 30,
            ["condition"] = new JsonObject
            {
                ["type"] = "idleAtLeast",
                ["milliseconds"] = 120_000,
                ["extension"] = "condition",
            },
            ["sequenceID"] = "routine",
            ["extension"] = "rule",
        });
        JsonObject phrase = profile["speech"]!["phrases"]![0]!.AsObject();
        phrase["trigger"] = new JsonObject
        {
            ["type"] = "sequence",
            ["sequenceID"] = "routine",
            ["extension"] = "trigger",
        };
        phrase["extension"] = "phrase";
        profile["speech"]!["placement"] = new JsonObject
        {
            ["preferredPosition"] = "above",
            ["horizontalOffset"] = 24,
            ["gap"] = 12,
        };
        return document;
    }

    private static JsonObject CreateAnimation(string? fallback) => new()
    {
        ["fallbackMotionID"] = fallback,
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

    private static JsonObject CreateTheme(string style) => new()
    {
        ["colorStyle"] = style,
        ["customBackgroundColor"] = new JsonObject { ["red"] = 1, ["green"] = 1, ["blue"] = 1 },
        ["customTextColor"] = new JsonObject { ["red"] = 0, ["green"] = 0, ["blue"] = 0 },
        ["backgroundOpacity"] = 0.96,
        ["fontSize"] = 14,
        ["contentPadding"] = 12,
        ["cornerRadius"] = 14,
        ["showsTail"] = false,
        ["tailAlignment"] = "center",
    };

    private sealed class TemporaryDirectory : IDisposable
    {
        public TemporaryDirectory()
        {
            Path = System.IO.Path.Combine(
                System.IO.Path.GetTempPath(),
                "MonglePet.Settings.Tests",
                Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(Path);
            SettingsPath = System.IO.Path.Combine(Path, "settings.json");
        }

        public string Path { get; }

        public string SettingsPath { get; }

        public AppSettingsStore CreateStore(
            Guid? temporaryId = null,
            Guid? quarantineId = null,
            Func<Guid?, string, long?>? cycleResolver = null,
            Func<Guid?, bool>? definitionAvailabilityResolver = null) => new(
                SettingsPath,
                temporaryIdGenerator: () => temporaryId ?? Guid.NewGuid(),
                quarantineIdGenerator: () => quarantineId ?? Guid.NewGuid(),
                legacyMotionCycleMillisecondsResolver: cycleResolver,
                legacyPetDefinitionAvailabilityResolver:
                    definitionAvailabilityResolver);

        public void Dispose()
        {
            if (Directory.Exists(Path))
            {
                Directory.Delete(Path, recursive: true);
            }
        }
    }
}
