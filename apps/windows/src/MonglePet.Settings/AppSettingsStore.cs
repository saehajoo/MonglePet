using System.Text.Json;
using System.Text.Json.Nodes;

namespace MonglePet.Settings;

public sealed class AppSettingsStore
{
    public const int CurrentSchemaVersion = 16;
    public const int MaximumFileSize = 5 * 1024 * 1024;

    private static readonly JsonSerializerOptions SerializerOptions = new()
    {
        WriteIndented = true,
    };

    private readonly Func<Guid> _temporaryIdGenerator;
    private readonly Func<Guid> _quarantineIdGenerator;
    private readonly Func<Guid> _settingsIdGenerator;
    private readonly Func<Guid?, string, long?>? _legacyMotionCycleMillisecondsResolver;
    private readonly Func<Guid?, bool>? _legacyPetDefinitionAvailabilityResolver;
    private JsonObject? _document;
    private AppSettings? _settings;
    private bool _hasLoaded;

    public AppSettingsStore(
        string settingsPath,
        Func<Guid>? temporaryIdGenerator = null,
        Func<Guid>? quarantineIdGenerator = null,
        Func<Guid?, string, long?>? legacyMotionCycleMillisecondsResolver = null,
        Func<Guid?, bool>? legacyPetDefinitionAvailabilityResolver = null,
        Func<Guid>? settingsIdGenerator = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(settingsPath);
        try
        {
            SettingsPath = Path.GetFullPath(settingsPath);
        }
        catch (Exception exception) when (exception is ArgumentException or NotSupportedException)
        {
            throw Error(AppSettingsError.InvalidSettingsPath, settingsPath, exception);
        }

        _temporaryIdGenerator = temporaryIdGenerator ?? Guid.NewGuid;
        _quarantineIdGenerator = quarantineIdGenerator ?? Guid.NewGuid;
        _settingsIdGenerator = settingsIdGenerator ?? Guid.NewGuid;
        _legacyMotionCycleMillisecondsResolver = legacyMotionCycleMillisecondsResolver;
        _legacyPetDefinitionAvailabilityResolver = legacyPetDefinitionAvailabilityResolver;
    }

    public string SettingsPath { get; }

    public bool IsWritingEnabled { get; private set; } = true;

    public AppSettingsLoadResult Load()
    {
        _hasLoaded = true;
        if (!File.Exists(SettingsPath))
        {
            _document = DefaultAppSettingsDocument.Create(_settingsIdGenerator);
            AppSettingsDocumentMappingResult mapped =
                AppSettingsDocumentMapper.FromDocument(_document, _settingsIdGenerator);
            _settings = mapped.Settings;
            IsWritingEnabled = true;
            return Result(
                _settings.SelectedPetInstanceId,
                AppSettingsLoadSource.Defaults,
                settings: _settings,
                recoveryIssues: mapped.Issues);
        }

        try
        {
            var file = new FileInfo(SettingsPath);
            if (file.Length > MaximumFileSize)
            {
                return RecoverCorruptFile("설정 파일이 5MiB 제한을 초과해 격리했습니다.");
            }

            JsonNode? parsed;
            using (var stream = new FileStream(
                       SettingsPath,
                       FileMode.Open,
                       FileAccess.Read,
                       FileShare.Read,
                       bufferSize: 64 * 1024,
                       FileOptions.SequentialScan))
            {
                parsed = JsonNode.Parse(
                    stream,
                    nodeOptions: null,
                    documentOptions: new JsonDocumentOptions
                    {
                        AllowTrailingCommas = false,
                        CommentHandling = JsonCommentHandling.Disallow,
                        MaxDepth = 128,
                    });
            }
            if (parsed is not JsonObject document || !TryReadSchemaVersion(document, out int schema))
            {
                return RecoverCorruptFile("설정 JSON 구조가 올바르지 않아 격리했습니다.");
            }

            if (schema > CurrentSchemaVersion)
            {
                _document = null;
                _settings = AppSettings.Default;
                IsWritingEnabled = false;
                return Result(
                    null,
                    AppSettingsLoadSource.NewerSchema,
                    [$"schema-v{schema} 원본을 보호하기 위해 설정 저장을 중단했습니다."],
                    schema,
                    settings: _settings);
            }

            if (schema < CurrentSchemaVersion)
            {
                if (schema == 1)
                {
                    Guid? legacySelected = ReadSelectedInstallationId(document, out _);
                    bool definitionAvailable =
                        _legacyPetDefinitionAvailabilityResolver?.Invoke(legacySelected)
                        ?? _legacyMotionCycleMillisecondsResolver is not null;
                    if (!definitionAvailable)
                    {
                        _document = null;
                        _settings = AppSettings.CreateDefault(_settingsIdGenerator)
                            .WithSelectedPetInstallationId(legacySelected, _settingsIdGenerator);
                        IsWritingEnabled = false;
                        return Result(
                            _settings.SelectedPetInstanceId,
                            AppSettingsLoadSource.UnsupportedLegacySchema,
                            ["schema-v1 마이그레이션에 필요한 선택 펫 정의를 찾지 못해 원본을 보호합니다."],
                            schema,
                            settings: _settings);
                    }
                }

                AppSettingsMigrationResult migration = AppSettingsMigrator.Migrate(
                    document,
                    schema,
                    _legacyMotionCycleMillisecondsResolver,
                    _settingsIdGenerator);
                AppSettingsDocumentMappingResult mapped =
                    AppSettingsDocumentMapper.FromDocument(migration.Document, _settingsIdGenerator);
                var issues = new List<string>
                {
                    $"schema-v{schema} 설정을 schema-v{CurrentSchemaVersion}으로 마이그레이션했습니다.",
                };
                issues.AddRange(migration.Issues);
                issues.AddRange(mapped.Issues.Select(issue => issue.ToString()));

                Write(migration.Document);
                _document = migration.Document;
                _settings = mapped.Settings;
                IsWritingEnabled = true;
                return Result(
                    _settings.SelectedPetInstanceId,
                    AppSettingsLoadSource.Migrated,
                    issues,
                    migratedFromSchema: schema,
                    settings: _settings,
                    recoveryIssues: mapped.Issues);
            }

            _document = document;
            AppSettingsDocumentMappingResult current =
                AppSettingsDocumentMapper.FromDocument(document, _settingsIdGenerator);
            _settings = current.Settings;
            IsWritingEnabled = true;
            return Result(
                _settings.SelectedPetInstanceId,
                current.Issues.Count == 0
                    ? AppSettingsLoadSource.File
                    : AppSettingsLoadSource.Recovered,
                current.Issues.Select(issue => issue.ToString()).ToArray(),
                settings: _settings,
                recoveryIssues: current.Issues);
        }
        catch (Exception exception) when (
            exception is JsonException or IOException or UnauthorizedAccessException or InvalidOperationException)
        {
            return RecoverCorruptFile("설정 파일을 읽을 수 없어 격리했습니다.");
        }
    }

    public void SaveSelectedPetInstallationId(Guid? installationId)
    {
        if (!_hasLoaded)
        {
            Load();
        }

        if (!IsWritingEnabled)
        {
            throw Error(
                AppSettingsError.WritingDisabled,
                "현재 앱이 지원하지 않는 설정 schema의 원본을 보호하고 있습니다.");
        }

        AppSettings current = _settings ?? AppSettings.CreateDefault(_settingsIdGenerator);
        AppSettings updated = current.WithSelectedPetInstallationId(installationId, _settingsIdGenerator);
        JsonObject next = AppSettingsDocumentMapper.ToDocument(updated, _document);
        Write(next);
        _document = next;
        _settings = updated;
        _hasLoaded = true;
    }

    public void Save(AppSettings settings)
    {
        ArgumentNullException.ThrowIfNull(settings);
        if (!_hasLoaded)
        {
            Load();
        }
        if (!IsWritingEnabled)
        {
            throw Error(
                AppSettingsError.WritingDisabled,
                "현재 앱이 지원하지 않는 설정 schema의 원본을 보호하고 있습니다.");
        }

        JsonObject next = AppSettingsDocumentMapper.ToDocument(settings, _document);
        Write(next);
        _document = next;
        _settings = settings;
        _hasLoaded = true;
    }

    private void Write(JsonObject document)
    {
        byte[] data = JsonSerializer.SerializeToUtf8Bytes(document, SerializerOptions);
        if (data.Length > MaximumFileSize)
        {
            throw Error(AppSettingsError.FileOperationFailed, "설정 파일이 5MiB 제한을 초과합니다.");
        }

        string parent = Path.GetDirectoryName(SettingsPath)
            ?? throw Error(AppSettingsError.InvalidSettingsPath, SettingsPath);
        string temporaryPath = Path.Combine(
            parent,
            $".settings-{_temporaryIdGenerator():D}.tmp");
        try
        {
            Directory.CreateDirectory(parent);
            using (var stream = new FileStream(
                       temporaryPath,
                       FileMode.CreateNew,
                       FileAccess.Write,
                       FileShare.None,
                       bufferSize: 64 * 1024,
                       FileOptions.WriteThrough))
            {
                stream.Write(data);
                stream.Flush(flushToDisk: true);
            }

            if (File.Exists(SettingsPath))
            {
                File.Move(temporaryPath, SettingsPath, overwrite: true);
            }
            else
            {
                File.Move(temporaryPath, SettingsPath);
            }
        }
        catch (AppSettingsException)
        {
            throw;
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            throw Error(AppSettingsError.FileOperationFailed, SettingsPath, exception);
        }
        finally
        {
            TryDeleteFile(temporaryPath);
        }
    }

    private AppSettingsLoadResult RecoverCorruptFile(string issue)
    {
        string parent = Path.GetDirectoryName(SettingsPath) ?? string.Empty;
        string quarantineName = $"settings.corrupt-{_quarantineIdGenerator():D}.json";
        string quarantinePath = Path.Combine(parent, quarantineName);
        try
        {
            File.Move(SettingsPath, quarantinePath);
            _document = DefaultAppSettingsDocument.Create(_settingsIdGenerator);
            _settings = AppSettingsDocumentMapper.FromDocument(_document, _settingsIdGenerator).Settings;
            IsWritingEnabled = true;
            return Result(
                _settings.SelectedPetInstanceId,
                AppSettingsLoadSource.Recovered,
                [$"{issue} ({quarantineName})"],
                settings: _settings);
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            _document = null;
            _settings = AppSettings.Default;
            IsWritingEnabled = false;
            return Result(
                null,
                AppSettingsLoadSource.Recovered,
                [$"손상된 설정 파일을 격리하지 못했습니다: {exception.Message}"],
                settings: _settings);
        }
    }

    private AppSettingsLoadResult Result(
        Guid? selected,
        AppSettingsLoadSource source,
        IReadOnlyList<string>? issues = null,
        int? schema = null,
        int? migratedFromSchema = null,
        AppSettings? settings = null,
        IReadOnlyList<SettingsRecoveryIssue>? recoveryIssues = null) => new(
            selected,
            source,
            issues ?? [],
            IsWritingEnabled,
            schema,
            migratedFromSchema,
            settings ?? _settings ?? AppSettings.Default,
            recoveryIssues ?? []);

    private static bool TryReadSchemaVersion(JsonObject document, out int schema)
    {
        schema = 0;
        return document["schemaVersion"] is JsonValue value &&
            value.TryGetValue(out schema) && schema > 0;
    }

    private static Guid? ReadSelectedInstallationId(
        JsonObject document,
        out bool recoveredInvalidId)
    {
        recoveredInvalidId = false;
        JsonNode? value = document["selectedPetInstallationID"];
        if (value is null)
        {
            return null;
        }

        if (value is JsonValue jsonValue &&
            jsonValue.TryGetValue(out string? text) &&
            Guid.TryParse(text, out Guid installationId))
        {
            return installationId;
        }

        recoveredInvalidId = true;
        return null;
    }

    private static void TryDeleteFile(string path)
    {
        try
        {
            if (File.Exists(path))
            {
                File.Delete(path);
            }
        }
        catch (IOException)
        {
        }
        catch (UnauthorizedAccessException)
        {
        }
    }

    private static AppSettingsException Error(
        AppSettingsError error,
        string detail,
        Exception? innerException = null) => new(error, detail, innerException);
}
