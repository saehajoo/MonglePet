using System.Security.Cryptography;

namespace MonglePet.Packages.Tests;

public sealed class BuiltInMongleContractTests
{
    [Fact]
    public void CommonBuiltInLoadsWithTenMotionsAndThirtySixFrames()
    {
        LoadedPetPackage package = new PetPackageLoader().LoadDirectory(FixturePath());

        Assert.Equal("kr.mapleroom.monglepet.builtin.mongle", package.Manifest.Id);
        Assert.Equal("몽글이", package.Manifest.DisplayName);
        Assert.Equal("1.0.1", package.Manifest.Version);
        Assert.Equal("운영자", package.Manifest.Author);
        Assert.Equal("기본", package.DefaultMotionId);
        Assert.Equal(10, package.Manifest.Motions.Count);
        Assert.Equal(36, package.Manifest.Motions.Sum(motion => motion.Frames.Count));
        Assert.All(package.Manifest.Motions, motion => Assert.True(motion.Loop));
    }

    [Fact]
    public void CommonBuiltInAtlasDigestsMatchTheHandoffContract()
    {
        var expected = new Dictionary<string, string>(StringComparer.Ordinal)
        {
            ["user-1c8c39ea-b9eb-4836-ba23-63015934a495.png"] = "ae379cb7785c8e01b46f07e1df59244327a29f0de72b262b305ec35be509d2e3",
            ["user-23c5957d-ac1b-4bfc-8e22-e992c44ad176.png"] = "f4659fe98a8b727e07bab3f0b4a31657b7cddd42deef424746bb459d69c5db42",
            ["user-343c62ee-5795-4071-8560-5de076e7d0c0.png"] = "d49b32daceac70dfc0f6c5882e3cdf6aa4718c47d102883880ce444f6f05723f",
            ["user-5978d5d1-cdfa-4b99-b9d0-bf301037cbc8.png"] = "847cba47b47617e7ad3f9676b1de4fbaf378171c996639754a33b5c7c7318e1a",
            ["user-735a4de3-7141-4bb3-a90b-a7a2d3a33421.png"] = "df99284ac3f9c542b2ea356fbd71af882c140a4345fe0ef91abd3ef69816cefa",
            ["user-7b12bbf7-8791-427d-a2a1-ac5f2099db79.png"] = "3f83e7741388df710f113cfcb9a8a4c44852785a68c1f321e8077c5766c6bf7d",
            ["user-88d7dd6a-f319-4b6f-a434-74062b30084c.png"] = "290e1f91ee9ce435c07a711b7104af3aaf97ba6b7088f757b9ab632f6c24c0d5",
            ["user-d4cbae90-1630-477d-b2c1-6eac680ac32f.png"] = "f6c209737bafee36b63c74f9d9135345ceb9ba94de1c923a6647a464e2ab1e91",
            ["user-e0a7325a-7a51-4bd9-8059-74e2878e4955.png"] = "84060bb36a96b7d10a2b69624327bb979241a6e1db9ce4856c591f54f4984764",
            ["user-fba0eae5-c271-4444-b722-7446d0fbcf07.png"] = "6615c6dde6b043d4e7c432532108a87426520e3757d47416a760c305cddb5536",
        };

        string assets = Path.Combine(FixturePath(), "assets");
        Assert.Equal(expected.Keys.Order(), Directory.GetFiles(assets, "*.png").Select(Path.GetFileName).Order());
        foreach ((string file, string digest) in expected)
        {
            using FileStream stream = File.OpenRead(Path.Combine(assets, file));
            Assert.Equal(digest, Convert.ToHexString(SHA256.HashData(stream)).ToLowerInvariant());
        }
    }

    private static string FixturePath() => Path.Combine(
        AppContext.BaseDirectory,
        "Fixtures",
        "BuiltInPets",
        "Mongle.monglepet");
}
