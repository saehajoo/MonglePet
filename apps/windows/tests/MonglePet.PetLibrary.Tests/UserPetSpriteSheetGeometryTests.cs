namespace MonglePet.PetLibrary.Tests;

public sealed class UserPetSpriteSheetGeometryTests
{
    [Fact]
    public void UniformGridCoversNonDivisibleSheetWithoutGaps()
    {
        IReadOnlyList<UserPetPixelRect> frames =
            UserPetSpriteSheetGeometry.CreateUniformGrid(7, 5, 2, 3);

        Assert.Equal(6, frames.Count);
        Assert.Equal(new UserPetPixelRect(0, 0, 2, 2), frames[0]);
        Assert.Equal(new UserPetPixelRect(4, 2, 3, 3), frames[5]);
        Assert.Equal(35, frames.Sum(frame => frame.Width * frame.Height));
    }

    [Fact]
    public void ReadingAndClickOrderRemainIndependent()
    {
        var fourth = (Id: Guid.NewGuid(), Rect: new UserPetPixelRect(10, 10, 5, 5));
        var first = (Id: Guid.NewGuid(), Rect: new UserPetPixelRect(0, 0, 5, 5));
        var third = (Id: Guid.NewGuid(), Rect: new UserPetPixelRect(0, 10, 5, 5));
        var values = new[] { fourth, first, third };

        Assert.Equal(
            [first.Id, third.Id, fourth.Id],
            UserPetSpriteSheetGeometry.ReadingOrder(values, value => value.Rect)
                .Select(value => value.Id));
        IReadOnlyList<Guid> clickOrder = [];
        clickOrder = UserPetSpriteSheetGeometry.ToggleClickOrder(clickOrder, fourth.Id);
        clickOrder = UserPetSpriteSheetGeometry.ToggleClickOrder(clickOrder, first.Id);
        clickOrder = UserPetSpriteSheetGeometry.ToggleClickOrder(clickOrder, third.Id);
        Assert.Equal([fourth.Id, first.Id, third.Id], clickOrder);
        Assert.Equal(
            [fourth.Id, third.Id],
            UserPetSpriteSheetGeometry.ToggleClickOrder(clickOrder, first.Id));
    }

    [Fact]
    public void GridInferenceUsesUniqueFrameOrigins()
    {
        UserPetPixelRect[] frames =
            UserPetSpriteSheetGeometry.CreateUniformGrid(700, 800, 8, 7).ToArray();

        Assert.Equal((8, 7), UserPetSpriteSheetGeometry.InferGridCounts(frames));
    }

    [Fact]
    public void WideAndTallSheetsRespectMinimumAndAvailableViewportHeight()
    {
        Assert.Equal(
            180,
            UserPetSpriteSheetGeometry.SuggestedCanvasHeight(4000, 400, 800, 600, 180));
        Assert.Equal(
            600,
            UserPetSpriteSheetGeometry.SuggestedCanvasHeight(400, 4000, 800, 600, 180));
    }
}
