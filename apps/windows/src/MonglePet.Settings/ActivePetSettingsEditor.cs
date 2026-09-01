using MonglePet.Core.Behavior;

namespace MonglePet.Settings;

public static class ActivePetSettingsEditor
{
    private const double NewInstanceOffset = 24;

    public static AppSettings Select(AppSettings settings, Guid instanceId)
    {
        ArgumentNullException.ThrowIfNull(settings);
        if (!settings.ActivePetInstances.Any(instance => instance.InstanceId == instanceId))
        {
            throw new ArgumentException("The selected pet instance does not exist.", nameof(instanceId));
        }

        return settings with { SelectedPetInstanceId = instanceId };
    }

    public static AppSettings AddSamePet(
        AppSettings settings,
        bool copiesSelectedSettings,
        Func<Guid>? idGenerator = null)
    {
        ArgumentNullException.ThrowIfNull(settings);
        ActivePetInstance selected = settings.SelectedPetInstance
            ?? throw new InvalidOperationException("A source pet instance is required.");
        BehaviorProfile selectedProfile = settings.SelectedBehaviorProfile
            ?? throw new InvalidOperationException("The source pet profile is missing.");
        return AddPetInstanceCore(
            settings,
            selected.PetKey,
            copiesSelectedSettings ? selectedProfile : null,
            copiesSelectedSettings ? selected.Overlay : OverlaySettings.Default,
            idGenerator);
    }

    public static AppSettings AddPetInstance(
        AppSettings settings,
        PetBehaviorKey petKey,
        BehaviorProfile? sourceProfile = null,
        OverlaySettings? sourceOverlay = null,
        Func<Guid>? idGenerator = null)
    {
        ArgumentNullException.ThrowIfNull(settings);
        ArgumentNullException.ThrowIfNull(petKey);
        return AddPetInstanceCore(
            settings,
            petKey,
            sourceProfile,
            sourceOverlay ?? OverlaySettings.Default,
            idGenerator);
    }

    private static AppSettings AddPetInstanceCore(
        AppSettings settings,
        PetBehaviorKey petKey,
        BehaviorProfile? sourceProfile,
        OverlaySettings sourceOverlay,
        Func<Guid>? idGenerator)
    {
        idGenerator ??= Guid.NewGuid;

        Guid instanceId = NextUniqueId(
            idGenerator,
            settings.ActivePetInstances.Select(instance => instance.InstanceId));
        Guid profileId = NextUniqueId(
            idGenerator,
            settings.BehaviorProfiles.Select(profile => profile.ProfileId));
        BehaviorProfile profile = sourceProfile is null
            ? BehaviorProfileDefaults.Create(petKey, profileId)
            : sourceProfile with { ProfileId = profileId, PetKey = petKey };
        OverlaySettings overlay = Offset(sourceOverlay);
        var added = new ActivePetInstance(
            instanceId,
            profileId,
            petKey,
            null,
            PetPresentation.Awake,
            overlay,
            0);

        return settings with
        {
            ActivePetInstances =
            [
                added,
                .. settings.ActivePetInstances
                    .OrderBy(instance => instance.DisplayOrder)
                    .Select((instance, index) => instance with { DisplayOrder = index + 1 }),
            ],
            BehaviorProfiles = [.. settings.BehaviorProfiles, profile],
            SelectedPetInstanceId = instanceId,
        };
    }

    public static AppSettings Rename(AppSettings settings, Guid instanceId, string? nickname)
    {
        string? normalized = string.IsNullOrWhiteSpace(nickname) ? null : nickname.Trim();
        if (normalized is not null &&
            AppSettingsLimits.TextLength(normalized) > AppSettingsLimits.MaximumPetNicknameLength)
        {
            throw new ArgumentException("The pet nickname is too long.", nameof(nickname));
        }

        return UpdateInstance(settings, instanceId, instance => instance with
        {
            Nickname = normalized,
        });
    }

    public static AppSettings SetPresentation(
        AppSettings settings,
        Guid instanceId,
        PetPresentation presentation) =>
        UpdateInstance(settings, instanceId, instance => instance with
        {
            Presentation = presentation,
        });

    public static AppSettings SetAllPresentations(
        AppSettings settings,
        PetPresentation presentation)
    {
        ArgumentNullException.ThrowIfNull(settings);
        return settings with
        {
            ActivePetInstances = settings.ActivePetInstances
                .Select(instance => instance with { Presentation = presentation })
                .ToList(),
        };
    }

    public static AppSettings SetOverlay(
        AppSettings settings,
        Guid instanceId,
        OverlaySettings overlay)
    {
        ArgumentNullException.ThrowIfNull(overlay);
        return UpdateInstance(settings, instanceId, instance => instance with
        {
            Overlay = overlay,
        });
    }

    public static AppSettings SetBehaviorProfile(
        AppSettings settings,
        Guid instanceId,
        BehaviorProfile profile)
    {
        ArgumentNullException.ThrowIfNull(settings);
        ArgumentNullException.ThrowIfNull(profile);
        ActivePetInstance instance = RequiredInstance(settings, instanceId);
        if (profile.ProfileId != instance.BehaviorProfileId || profile.PetKey != instance.PetKey)
        {
            throw new ArgumentException("The profile does not belong to the pet instance.", nameof(profile));
        }

        return settings with
        {
            BehaviorProfiles = settings.BehaviorProfiles
                .Select(current => current.ProfileId == profile.ProfileId ? profile : current)
                .ToList(),
        };
    }

    public static AppSettings ReplacePet(
        AppSettings settings,
        Guid instanceId,
        PetBehaviorKey petKey,
        Func<Guid>? idGenerator = null)
    {
        return ReplacePetCore(
            settings,
            instanceId,
            petKey,
            sourceProfile: null,
            idGenerator);
    }

    public static AppSettings ReplacePetCopyingProfile(
        AppSettings settings,
        Guid instanceId,
        PetBehaviorKey petKey,
        BehaviorProfile sourceProfile,
        Func<Guid>? idGenerator = null)
    {
        ArgumentNullException.ThrowIfNull(sourceProfile);
        return ReplacePetCore(
            settings,
            instanceId,
            petKey,
            sourceProfile,
            idGenerator);
    }

    private static AppSettings ReplacePetCore(
        AppSettings settings,
        Guid instanceId,
        PetBehaviorKey petKey,
        BehaviorProfile? sourceProfile,
        Func<Guid>? idGenerator)
    {
        ArgumentNullException.ThrowIfNull(settings);
        ArgumentNullException.ThrowIfNull(petKey);
        ActivePetInstance instance = RequiredInstance(settings, instanceId);
        if (instance.PetKey == petKey)
        {
            return Select(settings, instanceId);
        }
        idGenerator ??= Guid.NewGuid;
        Guid profileId = NextUniqueId(
            idGenerator,
            settings.BehaviorProfiles.Select(profile => profile.ProfileId));
        BehaviorProfile profile = sourceProfile is null
            ? BehaviorProfileDefaults.Create(petKey, profileId)
            : sourceProfile with
            {
                ProfileId = profileId,
                PetKey = petKey,
            };
        var referencedByOthers = settings.ActivePetInstances
            .Where(value => value.InstanceId != instanceId)
            .Select(value => value.BehaviorProfileId)
            .ToHashSet();

        return settings with
        {
            ActivePetInstances = settings.ActivePetInstances
                .Select(value => value.InstanceId == instanceId
                    ? value with { PetKey = petKey, BehaviorProfileId = profileId }
                    : value)
                .ToList(),
            BehaviorProfiles =
            [
                .. settings.BehaviorProfiles.Where(value =>
                    value.ProfileId != instance.BehaviorProfileId ||
                    referencedByOthers.Contains(value.ProfileId)),
                profile,
            ],
            SelectedPetInstanceId = instanceId,
        };
    }

    public static AppSettings ReplaceAllPetReferences(
        AppSettings settings,
        PetBehaviorKey sourcePetKey,
        PetBehaviorKey replacementPetKey,
        Func<Guid>? idGenerator = null)
    {
        ArgumentNullException.ThrowIfNull(settings);
        ArgumentNullException.ThrowIfNull(sourcePetKey);
        ArgumentNullException.ThrowIfNull(replacementPetKey);
        idGenerator ??= Guid.NewGuid;
        var profiles = settings.BehaviorProfiles.ToList();
        var usedProfileIds = profiles.Select(profile => profile.ProfileId).ToHashSet();
        var replacements = new Dictionary<Guid, Guid>();
        var instances = new List<ActivePetInstance>(settings.ActivePetInstances.Count);
        foreach (ActivePetInstance instance in settings.ActivePetInstances)
        {
            if (instance.PetKey != sourcePetKey)
            {
                instances.Add(instance);
                continue;
            }
            Guid profileId = NextUniqueId(idGenerator, usedProfileIds);
            usedProfileIds.Add(profileId);
            profiles.Add(BehaviorProfileDefaults.Create(replacementPetKey, profileId));
            replacements[instance.BehaviorProfileId] = profileId;
            instances.Add(instance with
            {
                PetKey = replacementPetKey,
                BehaviorProfileId = profileId,
            });
        }
        if (replacements.Count == 0)
        {
            return settings;
        }
        var referenced = instances.Select(instance => instance.BehaviorProfileId).ToHashSet();
        return settings with
        {
            ActivePetInstances = instances,
            BehaviorProfiles = profiles
                .Where(profile => referenced.Contains(profile.ProfileId) ||
                    !replacements.ContainsKey(profile.ProfileId))
                .ToList(),
        };
    }

    public static AppSettings ReassignPetKeepingIdentity(
        AppSettings settings,
        Guid instanceId,
        PetBehaviorKey petKey)
    {
        ArgumentNullException.ThrowIfNull(settings);
        ArgumentNullException.ThrowIfNull(petKey);
        ActivePetInstance instance = RequiredInstance(settings, instanceId);
        BehaviorProfile profile = settings.BehaviorProfiles.FirstOrDefault(value =>
            value.ProfileId == instance.BehaviorProfileId)
            ?? throw new InvalidOperationException("The pet behavior profile is missing.");
        return settings with
        {
            ActivePetInstances = settings.ActivePetInstances
                .Select(value => value.InstanceId == instanceId
                    ? value with { PetKey = petKey }
                    : value)
                .ToList(),
            BehaviorProfiles = settings.BehaviorProfiles
                .Select(value => value.ProfileId == profile.ProfileId
                    ? value with { PetKey = petKey }
                    : value)
                .ToList(),
        };
    }

    public static AppSettings RecoverUnreferencedInstallations(
        AppSettings settings,
        IEnumerable<Guid> installationIds,
        Func<Guid>? idGenerator = null)
    {
        ArgumentNullException.ThrowIfNull(settings);
        ArgumentNullException.ThrowIfNull(installationIds);
        idGenerator ??= Guid.NewGuid;
        var instances = settings.ActivePetInstances.ToList();
        var profiles = settings.BehaviorProfiles.ToList();
        var usedInstanceIds = instances.Select(value => value.InstanceId).ToHashSet();
        var usedProfileIds = instances.Select(value => value.BehaviorProfileId).ToHashSet();
        var allProfileIds = profiles.Select(value => value.ProfileId).ToHashSet();
        int nextOrder = instances.Count == 0
            ? 0
            : instances.Max(value => value.DisplayOrder) + 1;

        foreach (Guid installationId in installationIds
                     .Where(value => value != Guid.Empty)
                     .Distinct()
                     .Order())
        {
            var petKey = new PetBehaviorKey.Installed(installationId);
            if (instances.Any(value => value.PetKey == petKey))
            {
                continue;
            }

            BehaviorProfile? profile = profiles.FirstOrDefault(value =>
                value.PetKey == petKey && !usedProfileIds.Contains(value.ProfileId));
            if (profile is null)
            {
                Guid profileId = NextUniqueId(idGenerator, allProfileIds);
                allProfileIds.Add(profileId);
                profile = BehaviorProfileDefaults.Create(petKey, profileId);
                profiles.Add(profile);
            }
            usedProfileIds.Add(profile.ProfileId);
            Guid instanceId = NextUniqueId(idGenerator, usedInstanceIds);
            usedInstanceIds.Add(instanceId);
            instances.Add(new ActivePetInstance(
                instanceId,
                profile.ProfileId,
                petKey,
                null,
                PetPresentation.TuckedAway,
                OverlaySettings.Default,
                nextOrder++));
        }

        return instances.Count == settings.ActivePetInstances.Count
            ? settings
            : settings with
            {
                ActivePetInstances = instances,
                BehaviorProfiles = profiles,
            };
    }

    public static AppSettings Move(AppSettings settings, Guid instanceId, int targetIndex)
    {
        ArgumentNullException.ThrowIfNull(settings);
        var ordered = settings.ActivePetInstances
            .OrderBy(instance => instance.DisplayOrder)
            .ToList();
        int sourceIndex = ordered.FindIndex(instance => instance.InstanceId == instanceId);
        if (sourceIndex < 0)
        {
            throw new ArgumentException("The pet instance does not exist.", nameof(instanceId));
        }
        if (targetIndex < 0 || targetIndex >= ordered.Count)
        {
            throw new ArgumentOutOfRangeException(nameof(targetIndex));
        }

        ActivePetInstance moving = ordered[sourceIndex];
        ordered.RemoveAt(sourceIndex);
        ordered.Insert(targetIndex, moving);
        return settings with
        {
            ActivePetInstances = ordered
                .Select((instance, index) => instance with { DisplayOrder = index })
                .ToList(),
        };
    }

    public static AppSettings Remove(AppSettings settings, Guid instanceId)
    {
        ArgumentNullException.ThrowIfNull(settings);
        if (settings.ActivePetInstances.Count <= 1)
        {
            throw new InvalidOperationException("At least one active pet must remain.");
        }

        ActivePetInstance removing = RequiredInstance(settings, instanceId);
        var remaining = settings.ActivePetInstances
            .Where(instance => instance.InstanceId != instanceId)
            .OrderBy(instance => instance.DisplayOrder)
            .Select((instance, index) => instance with { DisplayOrder = index })
            .ToList();
        var referencedProfiles = remaining
            .Select(instance => instance.BehaviorProfileId)
            .ToHashSet();
        Guid selectedId = settings.SelectedPetInstanceId == instanceId
            ? remaining[0].InstanceId
            : settings.SelectedPetInstanceId;

        return settings with
        {
            ActivePetInstances = remaining,
            BehaviorProfiles = settings.BehaviorProfiles
                .Where(profile => profile.ProfileId != removing.BehaviorProfileId ||
                    referencedProfiles.Contains(profile.ProfileId))
                .ToList(),
            SelectedPetInstanceId = selectedId,
        };
    }

    private static AppSettings UpdateInstance(
        AppSettings settings,
        Guid instanceId,
        Func<ActivePetInstance, ActivePetInstance> update)
    {
        ArgumentNullException.ThrowIfNull(settings);
        ArgumentNullException.ThrowIfNull(update);
        _ = RequiredInstance(settings, instanceId);
        return settings with
        {
            ActivePetInstances = settings.ActivePetInstances
                .Select(instance => instance.InstanceId == instanceId ? update(instance) : instance)
                .ToList(),
        };
    }

    private static ActivePetInstance RequiredInstance(AppSettings settings, Guid instanceId) =>
        settings.ActivePetInstances.FirstOrDefault(instance => instance.InstanceId == instanceId)
        ?? throw new ArgumentException("The pet instance does not exist.", nameof(instanceId));

    private static OverlaySettings Offset(OverlaySettings overlay) => overlay with
    {
        OriginX = overlay.OriginX + NewInstanceOffset,
        OriginY = overlay.OriginY + NewInstanceOffset,
    };

    private static Guid NextUniqueId(Func<Guid> idGenerator, IEnumerable<Guid> existingIds)
    {
        var existing = existingIds.ToHashSet();
        for (int attempt = 0; attempt < 100; attempt++)
        {
            Guid id = idGenerator();
            if (id != Guid.Empty && existing.Add(id))
            {
                return id;
            }
        }
        throw new InvalidOperationException("A unique non-empty settings identifier could not be generated.");
    }
}
