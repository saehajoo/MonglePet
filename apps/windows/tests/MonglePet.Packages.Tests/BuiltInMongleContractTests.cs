using System.Security.Cryptography;

namespace MonglePet.Packages.Tests;

public sealed class BuiltInMongleContractTests
{
    [Fact]
    public void CommonBuiltInLoadsWithThirteenMotionsAndFiftyThreeFrames()
    {
        LoadedPetPackage package = new PetPackageLoader().LoadDirectory(FixturePath());

        Assert.Equal("kr.mapleroom.monglepet.builtin.mongle", package.Manifest.Id);
        Assert.Equal("몽글이", package.Manifest.DisplayName);
        Assert.Equal("1.0.3", package.Manifest.Version);
        Assert.Equal("운영자", package.Manifest.Author);
        Assert.Equal("기본", package.DefaultMotionId);
        Assert.Equal(13, package.Manifest.Motions.Count);
        Assert.Equal(53, package.Manifest.Motions.Sum(motion => motion.Frames.Count));
        Assert.All(package.Manifest.Motions, motion => Assert.True(motion.Loop));
    }

    [Fact]
    public void CommonBuiltInAtlasDigestsMatchTheHandoffContract()
    {
        var expected = new Dictionary<string, string>(StringComparer.Ordinal)
        {
            ["default.png"] = "22a13a0a95f7f1ab84c5748ab48ec98b85f4cb18da584f25a89a37e4bbc8f3fe",
            ["down.png"] = "367663b1f186c20526de49b56c360db2560840b7ee8d4362da93baeda5c1acf5",
            ["front.png"] = "5c0ea20c8ca838a5929e633d91a0777ba16c17c9ead9f36a6824fc056db0ca37",
            ["happy.png"] = "b515de9a2f43941cc683c957c29b1057733e3f51fb3d56287e92957c5482f620",
            ["left-bubbles.png"] = "6814ed312b3b87e4729da656cb6f7ca2f9e93b3a1123a80515118dddedb99440",
            ["left.png"] = "911d722b564838190f28edea2eaf6ce12f8eb88b63800e35c9fe28d1da839af8",
            ["right-bubbles.png"] = "04f00bdca5af83f29c3df29a3f03c0ae7fcbba65c7530232b4243d726834fb20",
            ["right.png"] = "2caa10b6f62506db9ffb69acb88953e1cc3d3066650d7ec4646b821028725b26",
            ["searching.png"] = "12d2516d2d3956fb502e41d4a3ef67cfc18923bdc14d51f78e06ac9d1c7e3445",
            ["sleeping.png"] = "fc4389614036dbf6f7a3dbc880ee6189bf77e2912d085031d62f7caea970deec",
            ["spouting.png"] = "0802d8501bf1cf9cd2166d4670162054adbf1178342de2090324204daa870d9f",
            ["up.png"] = "51008c3a86befc763e1d4234c9a202dc20e6aea4b44be31451cc44d743f6bf8b",
            ["working.png"] = "4876a5a78aa444fbcf5e18cfdfd84dbae4b90d0249f8381152533ecdcbd4c32e",
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
