using System.Text;
using System.Text.Json.Nodes;
using MonglePet.Core.Behavior;

namespace MonglePet.Settings.Tests;

public sealed class AppSettingsStoreTests
{
    [Fact]
    public void SchemaV14BehaviorModesMigrateToIndependentStationarySelectionAndRules()
    {
        JsonObject source = JsonNode.Parse(File.ReadAllText(Path.Combine(
            AppContext.BaseDirectory,
            "Fixtures",
            "schema-v14-stationary-rules.json")))!.AsObject();
        JsonNode expected = JsonNode.Parse(File.ReadAllText(Path.Combine(
            AppContext.BaseDirectory,
            "Fixtures",
            "schema-v15-stationary-rules.expected.json")))!;

        JsonObject migrated = AppSettingsMigrator.Migrate(
            source, 14, legacyMotionCycleMillisecondsResolver: null).Document;

        Assert.True(JsonNode.DeepEquals(expected, migrated));
    }

    [Fact]
    public void BuildsSettingsPathFromInjectedApplicationLocalDataRoot()
    {
        string root = Path.Combine("C:\\", "PackageLocalState");

        string path = AppSettingsPaths.FromAppLocalDataRoot(root);

        Assert.Equal(Path.Combine(root, "MonglePet", "settings.json"), path);
    }

    [Fact]
    public void MissingFileUsesDefaultsThenWritesCompleteSchemaV15Document()
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
        Assert.Equal(15, document["schemaVersion"]!.GetValue<int>());
        Assert.Equal("awake", document["activePetInstances"]?[0]?["presentation"]!.GetValue<string>());
        Assert.NotNull(document["activePetInstances"]?[0]?["overlay"]?["movementBoundary"]);
        Assert.NotNull(document["behaviorProfiles"]?[0]?["movement"]);
        Assert.Empty(Directory.EnumerateFiles(workspace.Path, ".settings-*.tmp"));
    }

    [Fact]
    public void DisplaySettingsAndUserPresentationRoundTripAsTypedValues()
    {
        using var workspace = new TemporaryDirectory();
        var store = workspace.CreateStore();
        AppSettings settings = store.Load().Settings!;
        AppSettings updated = settings
            .WithSelectedPresentation(PetPresentation.TuckedAway)
            .WithSelectedOverlay(settings.Overlay with
            {
                Width = 304,
                ClickThrough = true,
                Opacity = 0.65,
                PixelArtRendering = true,
            });

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
    public void SharedSchemaV10FixtureMigratesExactlyToSharedSchemaV11Fixture()
    {
        JsonObject source = JsonNode.Parse(File.ReadAllText(Path.Combine(
            AppContext.BaseDirectory,
            "Fixtures",
            "schema-v10-single-pet.json")))!.AsObject();
        Guid[] generatedIds =
        [
            Guid.Parse("22222222-2222-2222-2222-222222222222"),
            Guid.Parse("33333333-3333-3333-3333-333333333333"),
        ];
        int index = 0;

        AppSettingsMigrationResult migration = AppSettingsMigrator.Migrate(
            source,
            10,
            legacyMotionCycleMillisecondsResolver: null,
            settingsIdGenerator: () => generatedIds[index++],
            targetSchema: 11);
        JsonNode actual = migration.Document;
        JsonNode expected = JsonNode.Parse(File.ReadAllText(Path.Combine(
            AppContext.BaseDirectory,
            "Fixtures",
            "schema-v11-single-instance.expected.json")))!;

        Assert.True(JsonNode.DeepEquals(expected, actual));
    }

    [Fact]
    public void SharedSchemaV11BehaviorFixtureMigratesExactlyToSchemaV12Fixture()
    {
        JsonObject source = JsonNode.Parse(File.ReadAllText(Path.Combine(
            AppContext.BaseDirectory,
            "Fixtures",
            "schema-v11-behavior-references.json")))!.AsObject();
        JsonNode expected = JsonNode.Parse(File.ReadAllText(Path.Combine(
            AppContext.BaseDirectory,
            "Fixtures",
            "schema-v12-behavior-references.expected.json")))!;

        AppSettingsMigrationResult migration = AppSettingsMigrator.Migrate(
            source,
            11,
            legacyMotionCycleMillisecondsResolver: null,
            targetSchema: 12);

        Assert.True(JsonNode.DeepEquals(expected, migration.Document));
    }

    [Fact]
    public void SharedSchemaV13RandomFixtureMigratesThroughSchemaV15AndRoundTrips()
    {
        using var workspace = new TemporaryDirectory();
        File.Copy(Path.Combine(
            AppContext.BaseDirectory,
            "Fixtures",
            "schema-v13-random-behaviors.json"), workspace.SettingsPath);

        AppSettingsLoadResult loaded = workspace.CreateStore().Load();
        BehaviorProfile profile = Assert.IsType<BehaviorProfile>(loaded.Settings!.SelectedBehaviorProfile);

        Assert.Equal(AppSettingsLoadSource.Migrated, loaded.Source);
        Assert.Equal(15, ReadDocument(workspace.SettingsPath)["schemaVersion"]!.GetValue<int>());
        Assert.Equal(StationaryBehaviorMode.Random, profile.StationaryBehaviorMode);
        Assert.Equal(["__monglepet_default_behavior__", "walk"], profile.RandomSequences);
        Assert.True(profile.Movement.FreeRoaming.RandomizesDwell);
        Assert.Equal(2_000, profile.Movement.FreeRoaming.DwellMinimumMilliseconds);
        Assert.Equal(profile.Movement.FreeRoaming, profile.Movement.CursorAvoiding.IdleFreeRoaming);

        workspace.CreateStore().Save(loaded.Settings!);
        BehaviorProfile reloaded = workspace.CreateStore().Load().Settings!.SelectedBehaviorProfile!;
        Assert.Equal(profile.StationaryBehaviorMode, reloaded.StationaryBehaviorMode);
        Assert.Equal(profile.RandomSequences.ToArray(), reloaded.RandomSequences.ToArray());
        Assert.Equal(profile.RulePriorityOrder.ToArray(), reloaded.RulePriorityOrder.ToArray());
        Assert.Equal(profile.Movement.FreeRoaming, reloaded.Movement.FreeRoaming);
        Assert.Equal(profile.Movement.CursorAvoiding, reloaded.Movement.CursorAvoiding);
    }

    [Fact]
    public void SamePetInstancesKeepIndependentProfilesAndOverlaysAfterReload()
    {
        using var workspace = new TemporaryDirectory();
        PetBehaviorKey key = new PetBehaviorKey.Installed(
            Guid.Parse("12121212-1212-1212-1212-121212121212"));
        Guid firstProfileId = Guid.Parse("13131313-1313-1313-1313-131313131313");
        Guid secondProfileId = Guid.Parse("14141414-1414-1414-1414-141414141414");
        Guid firstInstanceId = Guid.Parse("15151515-1515-1515-1515-151515151515");
        Guid secondInstanceId = Guid.Parse("16161616-1616-1616-1616-161616161616");
        BehaviorProfile firstProfile = BehaviorProfileDefaults.Create(key, firstProfileId) with
        {
            Movement = PetMovementSettings.Default with { Speed = 120 },
        };
        BehaviorProfile secondProfile = BehaviorProfileDefaults.Create(key, secondProfileId) with
        {
            Movement = PetMovementSettings.Default with { Speed = 360 },
        };
        AppSettings settings = new(
            [
                new ActivePetInstance(
                    firstInstanceId,
                    firstProfileId,
                    key,
                    "왼쪽 몽글이",
                    PetPresentation.Awake,
                    OverlaySettings.Default with { OriginX = 100, Width = 180 },
                    0),
                new ActivePetInstance(
                    secondInstanceId,
                    secondProfileId,
                    key,
                    "오른쪽 몽글이",
                    PetPresentation.TuckedAway,
                    OverlaySettings.Default with { OriginX = 900, Width = 300 },
                    1),
            ],
            [firstProfile, secondProfile],
            secondInstanceId);
        settings = settings.WithSelectedOverlay(settings.Overlay with { OriginX = 950 });
        settings = settings.WithSelectedBehaviorProfile(
            settings.SelectedBehaviorProfile! with
            {
                Movement = settings.SelectedBehaviorProfile!.Movement with { Speed = 400 },
            });
        var store = workspace.CreateStore();
        store.Load();

        store.Save(settings);
        AppSettings reloaded = workspace.CreateStore().Load().Settings!;

        Assert.Equal(secondInstanceId, reloaded.SelectedPetInstanceId);
        Assert.Equal(2, reloaded.ActivePetInstances.Count);
        Assert.Equal([100d, 950d], reloaded.ActivePetInstances.Select(instance => instance.Overlay.OriginX));
        Assert.Equal([180d, 300d], reloaded.ActivePetInstances.Select(instance => instance.Overlay.Width));
        Assert.Equal([120d, 400d], reloaded.ActivePetInstances.Select(instance =>
            reloaded.BehaviorProfiles.Single(profile => profile.ProfileId == instance.BehaviorProfileId).Movement.Speed));
        Assert.NotEqual(
            reloaded.ActivePetInstances[0].BehaviorProfileId,
            reloaded.ActivePetInstances[1].BehaviorProfileId);
    }

    [Fact]
    public void SchemaV11RepairsIdentifiersReferencesAndOrderPerItem()
    {
        using var workspace = new TemporaryDirectory();
        JsonObject source = CreateCurrentSchemaDocument();
        JsonObject first = source["activePetInstances"]![0]!.AsObject();
        first["displayOrder"] = 4;
        first["extension"] = "keep-first";
        JsonObject duplicate = first.DeepClone().AsObject();
        duplicate["nickname"] = " second ";
        duplicate["displayOrder"] = 1;
        duplicate["extension"] = "keep-second";
        source["activePetInstances"]!.AsArray().Add(duplicate);
        JsonObject missing = first.DeepClone().AsObject();
        missing["instanceID"] = "not-a-uuid";
        missing["behaviorProfileID"] = "ffffffff-ffff-ffff-ffff-ffffffffffff";
        missing["displayOrder"] = -1;
        missing["extension"] = "keep-third";
        source["activePetInstances"]!.AsArray().Add(missing);
        source["selectedPetInstanceID"] = "ffffffff-ffff-ffff-ffff-ffffffffffff";
        var ids = new Queue<Guid>(
        [
            Guid.Parse("17171717-1717-1717-1717-171717171717"),
            Guid.Parse("18181818-1818-1818-1818-181818181818"),
            Guid.Parse("19191919-1919-1919-1919-191919191919"),
            Guid.Parse("20202020-2020-2020-2020-202020202020"),
        ]);
        File.WriteAllText(workspace.SettingsPath, source.ToJsonString());
        var store = workspace.CreateStore(settingsIdGenerator: ids.Dequeue);

        AppSettingsLoadResult loaded = store.Load();
        AppSettings repaired = loaded.Settings!;

        Assert.Equal(AppSettingsLoadSource.Recovered, loaded.Source);
        Assert.Equal(3, repaired.ActivePetInstances.Count);
        Assert.Equal([0, 1, 2], repaired.ActivePetInstances.Select(instance => instance.DisplayOrder));
        Assert.Equal(3, repaired.ActivePetInstances.Select(instance => instance.InstanceId).Distinct().Count());
        Assert.Equal(3, repaired.ActivePetInstances.Select(instance => instance.BehaviorProfileId).Distinct().Count());
        Assert.Equal(repaired.ActivePetInstances[0].InstanceId, repaired.SelectedPetInstanceId);
        Assert.Equal("second", repaired.ActivePetInstances[0].Nickname);
        Assert.All(repaired.ActivePetInstances, instance => Assert.Equal(
            instance.PetKey,
            repaired.BehaviorProfiles.Single(profile => profile.ProfileId == instance.BehaviorProfileId).PetKey));

        store.Save(repaired);
        JsonArray savedInstances = ReadDocument(workspace.SettingsPath)["activePetInstances"]!.AsArray();
        Assert.Contains(savedInstances, node => node?["extension"]?.GetValue<string>() == "keep-first");
        Assert.Contains(savedInstances, node => node?["extension"]?.GetValue<string>() == "keep-second");
        Assert.Contains(savedInstances, node => node?["extension"]?.GetValue<string>() == "keep-third");
    }

    [Fact]
    public void CurrentSchemaRepairsDuplicateAndInvalidProfileIdsAndPetOwnership()
    {
        using var workspace = new TemporaryDirectory();
        JsonObject source = CreateCurrentSchemaDocument();
        JsonObject originalProfile = source["behaviorProfiles"]![0]!.AsObject();
        originalProfile["extension"] = "original";
        JsonObject duplicateProfile = originalProfile.DeepClone().AsObject();
        duplicateProfile["extension"] = "duplicate";
        source["behaviorProfiles"]!.AsArray().Add(duplicateProfile);
        JsonObject invalidProfile = originalProfile.DeepClone().AsObject();
        invalidProfile["profileID"] = "not-a-uuid";
        invalidProfile["extension"] = "invalid";
        source["behaviorProfiles"]!.AsArray().Add(invalidProfile);
        JsonObject instance = source["activePetInstances"]![0]!.AsObject();
        instance["petKey"] = new JsonObject
        {
            ["type"] = "installed",
            ["installationID"] = "21212121-2121-2121-2121-212121212121",
        };
        File.WriteAllText(workspace.SettingsPath, source.ToJsonString());
        var store = workspace.CreateStore();

        AppSettingsLoadResult loaded = store.Load();
        AppSettings repaired = loaded.Settings!;

        Assert.Equal(AppSettingsLoadSource.Recovered, loaded.Source);
        Assert.Equal(4, repaired.BehaviorProfiles.Count);
        Assert.Equal(4, repaired.BehaviorProfiles.Select(profile => profile.ProfileId).Distinct().Count());
        Assert.Equal(repaired.SelectedPetInstance!.PetKey, repaired.SelectedBehaviorProfile!.PetKey);

        store.Save(repaired);
        JsonArray savedProfiles = ReadDocument(workspace.SettingsPath)["behaviorProfiles"]!.AsArray();
        Assert.Contains(savedProfiles, node => node?["extension"]?.GetValue<string>() == "original");
        Assert.Contains(savedProfiles, node => node?["extension"]?.GetValue<string>() == "duplicate");
        Assert.Contains(savedProfiles, node => node?["extension"]?.GetValue<string>() == "invalid");
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
        Assert.Equal(StationaryBehaviorMode.Fixed, profile.StationaryBehaviorMode);
        Assert.Null(profile.StationarySequenceId);
        Assert.Equal(BehaviorMotionReferences.DefaultSequence, sequence.Id);
        Assert.True(sequence.Repeats);
        Assert.Equal(BehaviorMotionReferences.CurrentPetDefault, step.MotionId);
        Assert.Equal(1, step.RepeatCount);
        Assert.Empty(profile.AutomaticRules);
    }

    [Fact]
    public void UpdatingSelectionMigratesV10AndPreservesUnknownFields()
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

        JsonObject instance = saved["activePetInstances"]![0]!.AsObject();
        Assert.Equal(selectedId.ToString("D"), instance["petKey"]?["installationID"]!.GetValue<string>());
        Assert.Equal("tuckedAway", instance["presentation"]!.GetValue<string>());
        Assert.Equal(321, instance["overlay"]?["width"]?.GetValue<int>());
        Assert.Equal("keep", instance["overlay"]?["windowsOnlyMarker"]?.GetValue<string>());
        Assert.True(saved["unrecognizedCurrentField"]?["nested"]?.GetValue<bool>());
    }

    [Fact]
    public void InvalidSelectedUuidRecoversOnlyThatField()
    {
        using var workspace = new TemporaryDirectory();
        JsonObject source = CreateCurrentSchemaDocument();
        source["selectedPetInstanceID"] = "not-a-uuid";
        source["activePetInstances"]![0]!["overlay"]!["width"] = 222;
        File.WriteAllText(workspace.SettingsPath, source.ToJsonString());
        var store = workspace.CreateStore();

        AppSettingsLoadResult loaded = store.Load();
        store.SaveSelectedPetInstallationId(null);
        JsonObject saved = ReadDocument(workspace.SettingsPath);

        Assert.Equal(AppSettingsLoadSource.Recovered, loaded.Source);
        Assert.Null(loaded.SelectedPetInstallationId);
        Assert.NotEmpty(loaded.Issues);
        Assert.Equal(222, saved["activePetInstances"]?[0]?["overlay"]?["width"]?.GetValue<int>());
        Assert.Equal(
            saved["activePetInstances"]?[0]?["instanceID"]?.GetValue<string>(),
            saved["selectedPetInstanceID"]?.GetValue<string>());
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
            "{\"schemaVersion\":16,\"futureValue\":true}");
        File.WriteAllBytes(workspace.SettingsPath, original);
        var store = workspace.CreateStore();

        AppSettingsLoadResult loaded = store.Load();
        AppSettingsException exception = Assert.Throws<AppSettingsException>(
            () => store.SaveSelectedPetInstallationId(Guid.NewGuid()));

        Assert.Equal(AppSettingsLoadSource.NewerSchema, loaded.Source);
        Assert.Equal(16, loaded.PreservedSchemaVersion);
        Assert.False(loaded.IsWritingEnabled);
        Assert.Equal(AppSettingsError.WritingDisabled, exception.Error);
        Assert.Equal(original, File.ReadAllBytes(workspace.SettingsPath));
    }

    [Fact]
    public void V1FixtureMigratesMotionDurationsAndAllLaterSchemasToV14()
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
        Assert.Equal(15, migrated["schemaVersion"]!.GetValue<int>());
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
    [InlineData(10)]
    public void EachLegacyStartingSchemaMigratesSequentiallyAndPreservesValues(int schema)
    {
        using var workspace = new TemporaryDirectory();
        JsonObject source = schema == 10 ? CreateSchemaV10Document() : CreateLegacyDocument(schema);
        File.WriteAllText(workspace.SettingsPath, source.ToJsonString());

        AppSettingsLoadResult loaded = workspace.CreateStore().Load();
        JsonObject migrated = ReadDocument(workspace.SettingsPath);
        JsonObject overlay = migrated["activePetInstances"]![0]!["overlay"]!.AsObject();
        JsonObject profile = migrated["behaviorProfiles"]![0]!.AsObject();
        JsonObject movement = profile["movement"]!.AsObject();
        JsonObject speech = profile["speech"]!.AsObject();

        Assert.Equal(AppSettingsLoadSource.Migrated, loaded.Source);
        Assert.Equal(schema, loaded.MigratedFromSchemaVersion);
        Assert.True(loaded.IsWritingEnabled);
        Assert.Equal(15, migrated["schemaVersion"]!.GetValue<int>());
        Assert.Equal("preserve", overlay["qaMarker"]!.GetValue<string>());
        Assert.Equal(schema >= 3 ? 240 : 160, movement["freeRoaming"]?["speed"]!.GetValue<double>());
        string? roamingBehaviorId = movement["freeRoaming"]?["behavior"]?["fallbackBehaviorID"]?.GetValue<string?>();
        string? roamingMotionId = profile["sequences"]!.AsArray()
            .OfType<JsonObject>()
            .SingleOrDefault(sequence => sequence["id"]?.GetValue<string?>() == roamingBehaviorId)?["steps"]?[0]?["motionID"]?.GetValue<string?>();
        Assert.Equal(schema >= 3 ? "walk" : null, roamingMotionId);
        Assert.Equal(schema >= 6 ? 444 : 320, movement["cursorAvoiding"]?["speed"]!.GetValue<double>());
        Assert.Equal(schema >= 7 ? 90_000 : 60_000, speech["periodicIntervalMilliseconds"]!.GetValue<int>());
        Assert.Equal(schema >= 8 ? "mint" : "system", speech["theme"]?["colorStyle"]?.GetValue<string>());
        Assert.Equal(schema >= 9 ? "sequential" : "random", speech["periodicOrder"]!.GetValue<string>());
        Assert.Equal(schema == 10 ? "above" : "automatic", speech["placement"]?["preferredPosition"]?.GetValue<string>());
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

        Assert.Equal(AppSettingsLoadSource.Migrated, loaded.Source);
        Assert.Empty(Assert.IsAssignableFrom<IReadOnlyList<SettingsRecoveryIssue>>(loaded.RecoveryIssues));
        Assert.Equal(PetPresentation.TuckedAway, settings.LastUserPresentation);
        Assert.Equal(240, settings.Overlay.Width);
        Assert.Equal(MovementBoundaryMode.SelectedDisplay, settings.Overlay.MovementBoundary.Mode);
        Assert.Equal(StationaryBehaviorMode.Fixed, profile.StationaryBehaviorMode);
        Assert.NotNull(profile.StationarySequenceId);
        Assert.Equal(PetMovementMode.FreeRoaming, profile.Movement.Mode);
        Assert.True(profile.Movement.FreeRoaming.Behavior.UsesDirectionalBehaviors);
        string leftBehaviorId = Assert.IsType<string>(
            profile.Movement.FreeRoaming.Behavior.DirectionBehaviorIds.Left);
        Assert.Equal("walk-left", Assert.Single(profile.Sequences.Single(
            sequence => sequence.Id == leftBehaviorId).Steps).MotionId);
        string pettingBehaviorId = Assert.IsType<string>(profile.PettingBehaviorId);
        Assert.Equal("happy", Assert.Single(profile.Sequences.Single(
            sequence => sequence.Id == pettingBehaviorId).Steps).MotionId);
        Assert.Equal(PetSpeechPeriodicOrder.Sequential, profile.Speech.PeriodicOrder);
        Assert.Equal(PetSpeechBubbleColorStyle.Mint, profile.Speech.Theme.ColorStyle);
        Assert.Equal(PetSpeechBubblePreferredPosition.Above, profile.Speech.Placement.PreferredPosition);
        Assert.IsType<RuleCondition.IdleAtLeast>(Assert.Single(profile.AutomaticRules).Condition);
        Assert.IsType<PetSpeechTrigger.Sequence>(Assert.Single(profile.Speech.Phrases).Trigger);

        store.Save(settings.WithSelectedOverlay(settings.Overlay with { Width = 260 }));
        JsonObject saved = ReadDocument(workspace.SettingsPath);

        Assert.Equal(260, saved["activePetInstances"]?[0]?["overlay"]?["width"]?.GetValue<double>());
        Assert.Equal("top", saved["extension"]?.GetValue<string>());
        Assert.Equal("overlay", saved["activePetInstances"]?[0]?["overlay"]?["extension"]?.GetValue<string>());
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
        JsonObject source = CreateCurrentSchemaDocument();
        source["selectedPetInstanceID"] = "not-a-uuid";
        JsonObject storedInstance = source["activePetInstances"]![0]!.AsObject();
        storedInstance["presentation"] = "suspended";
        JsonObject overlay = storedInstance["overlay"]!.AsObject();
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
        profile["stationaryBehaviorMode"] = "unexpected";
        profile["stationarySequenceID"] = "missing";
        profile["sequences"]![0]!["steps"]!.AsArray().Add(new JsonObject
        {
            ["motionID"] = " bad ",
            ["repeatCount"] = 0,
        });
        profile["automaticRules"]![0]!["isEnabled"] = true;
        profile["automaticRules"]![0]!["sequenceID"] = "missing";
        profile["automaticRules"]!.AsArray().Add(new JsonObject
        {
            ["id"] = "invalid",
            ["sequenceID"] = "routine",
        });
        JsonObject movement = profile["movement"]!.AsObject();
        JsonObject freeRoaming = movement["freeRoaming"]!.AsObject();
        freeRoaming["speed"] = -1;
        JsonObject animation = freeRoaming["behavior"]!.AsObject();
        animation["usesDirectionalBehaviors"] = false;
        animation["usesDiagonalBehaviors"] = true;
        animation["directionBehaviorIDs"]!["right"] = " invalid ";
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
        BehaviorProfile recovered = Assert.IsType<BehaviorProfile>(settings.SelectedBehaviorProfile);

        Assert.Equal(AppSettingsLoadSource.Recovered, loaded.Source);
        Assert.Null(settings.SelectedPetInstallationId);
        Assert.Equal(PetPresentation.Awake, settings.LastUserPresentation);
        Assert.Equal(384, settings.Overlay.Width);
        Assert.Equal(MovementBoundaryMode.AllDisplays, settings.Overlay.MovementBoundary.Mode);
        Assert.Equal(StationaryBehaviorMode.Fixed, recovered.StationaryBehaviorMode);
        Assert.Null(recovered.StationarySequenceId);
        Assert.Single(recovered.Sequences.Single(sequence => sequence.Id == "routine").Steps);
        Assert.False(Assert.Single(recovered.AutomaticRules).IsEnabled);
        Assert.Equal(160, recovered.Movement.FreeRoaming.Speed);
        Assert.False(recovered.Movement.FreeRoaming.Behavior.UsesDiagonalBehaviors);
        Assert.Null(recovered.Movement.FreeRoaming.Behavior.DirectionBehaviorIds.Right);
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
        JsonObject source = CreateCurrentSchemaDocument();
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
    public void CurrentSchemaKeepsOnlyOneIdleRuleAndOneRulePerApplication()
    {
        using var workspace = new TemporaryDirectory();
        JsonObject source = CreateCurrentSchemaDocument();
        JsonArray rules = source["behaviorProfiles"]![0]!["automaticRules"]!.AsArray();
        JsonObject idleDuplicate = rules[0]!.DeepClone().AsObject();
        idleDuplicate["id"] = "91000000-0000-0000-0000-000000000001";
        JsonObject application = new()
        {
            ["id"] = "91000000-0000-0000-0000-000000000002",
            ["isEnabled"] = true,
            ["priority"] = 0,
            ["condition"] = new JsonObject
            {
                ["type"] = "application",
                ["bundleIdentifier"] = "exe:notepad.exe",
            },
            ["sequenceID"] = "routine",
        };
        JsonObject applicationDuplicate = application.DeepClone().AsObject();
        applicationDuplicate["id"] = "91000000-0000-0000-0000-000000000003";
        rules.Add(idleDuplicate);
        rules.Add(application);
        rules.Add(applicationDuplicate);
        File.WriteAllText(workspace.SettingsPath, source.ToJsonString());

        AppSettingsLoadResult loaded = workspace.CreateStore().Load();
        IReadOnlyList<AutomaticRule> recovered =
            loaded.Settings!.SelectedBehaviorProfile!.AutomaticRules;

        Assert.Equal(AppSettingsLoadSource.Recovered, loaded.Source);
        Assert.Equal(2, recovered.Count);
        Assert.Single(recovered, rule => rule.Condition is RuleCondition.IdleAtLeast);
        Assert.Single(recovered, rule => rule.Condition is RuleCondition.Application);
        Assert.Equal(2, loaded.RecoveryIssues!.Count(issue =>
            issue.Kind == SettingsRecoveryKind.DroppedRule));
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
            store.Save(settings.WithSelectedOverlay(settings.Overlay with { Width = double.NaN })));

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

    private static JsonObject CreateSchemaV11Document()
    {
        JsonObject document = CreateSchemaV10Document();
        const string instanceId = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa";
        const string profileId = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb";
        JsonObject profile = document["behaviorProfiles"]![0]!.AsObject();
        profile["profileID"] = profileId;
        JsonObject instance = new()
        {
            ["instanceID"] = instanceId,
            ["behaviorProfileID"] = profileId,
            ["petKey"] = profile["petKey"]!.DeepClone(),
            ["nickname"] = null,
            ["presentation"] = document["lastUserPresentation"]!.DeepClone(),
            ["overlay"] = document["overlay"]!.DeepClone(),
            ["displayOrder"] = 0,
        };
        document["schemaVersion"] = 11;
        document["selectedPetInstanceID"] = instanceId;
        document["activePetInstances"] = new JsonArray(instance);
        document.Remove("selectedPetInstallationID");
        document.Remove("lastUserPresentation");
        document.Remove("overlay");
        return document;
    }

    private static JsonObject CreateCurrentSchemaDocument() =>
        AppSettingsMigrator.Migrate(
            CreateSchemaV11Document(),
            11,
            legacyMotionCycleMillisecondsResolver: null).Document;

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
            Func<Guid?, bool>? definitionAvailabilityResolver = null,
            Func<Guid>? settingsIdGenerator = null) => new(
                SettingsPath,
                temporaryIdGenerator: () => temporaryId ?? Guid.NewGuid(),
                quarantineIdGenerator: () => quarantineId ?? Guid.NewGuid(),
                legacyMotionCycleMillisecondsResolver: cycleResolver,
                legacyPetDefinitionAvailabilityResolver:
                    definitionAvailabilityResolver,
                settingsIdGenerator: settingsIdGenerator);

        public void Dispose()
        {
            if (Directory.Exists(Path))
            {
                Directory.Delete(Path, recursive: true);
            }
        }
    }
}
