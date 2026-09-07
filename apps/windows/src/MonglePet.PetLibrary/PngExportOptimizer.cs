using System.Buffers.Binary;
using System.IO.Compression;
using System.Security.Cryptography;
using System.Text;

namespace MonglePet.PetLibrary;

public interface IPngExportOptimizer
{
    PngExportOptimizationResult Optimize(
        ReadOnlyMemory<byte> originalBytes,
        CancellationToken cancellationToken = default);
}

public sealed record PngExportOptimizationResult(
    byte[] Bytes,
    bool IsOptimized,
    bool IsCacheHit);

public sealed class PngExportOptimizer : IPngExportOptimizer
{
    public const string CurrentImplementationVersion = "adaptive-filter-v1";
    public const long DefaultMaximumCacheBytes = 256L * 1024 * 1024;

    private static readonly byte[] Signature = [137, 80, 78, 71, 13, 10, 26, 10];
    private readonly object _cacheLock = new();
    private readonly string _cacheRoot;
    private readonly long _maximumCacheBytes;
    private readonly string _implementationVersion;

    public PngExportOptimizer(
        string? cacheRoot = null,
        long maximumCacheBytes = DefaultMaximumCacheBytes,
        string implementationVersion = CurrentImplementationVersion)
    {
        ArgumentOutOfRangeException.ThrowIfNegative(maximumCacheBytes);
        ArgumentException.ThrowIfNullOrWhiteSpace(implementationVersion);
        _cacheRoot = Path.GetFullPath(cacheRoot ?? Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "MonglePet",
            "Cache",
            "PngExport"));
        _maximumCacheBytes = maximumCacheBytes;
        _implementationVersion = implementationVersion;
    }

    public PngExportOptimizationResult Optimize(
        ReadOnlyMemory<byte> originalBytes,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        byte[] original = originalBytes.ToArray();
        if (!PngCodec.TryDecode(original, out DecodedPng? decoded) || decoded is null)
        {
            return new(original, false, false);
        }

        string key = Convert.ToHexString(SHA256.HashData(original)).ToLowerInvariant();
        string versionKey = Convert.ToHexString(SHA256.HashData(
            Encoding.UTF8.GetBytes(_implementationVersion))).ToLowerInvariant()[..16];
        string cachePath = Path.Combine(_cacheRoot, $"{key}-{versionKey}.png");
        byte[]? cached = TryReadCache(cachePath);
        if (cached is not null &&
            cached.Length < original.Length &&
            PngCodec.IsPixelEquivalent(decoded, cached))
        {
            TryTouch(cachePath);
            return new(cached, true, true);
        }
        if (cached is not null)
        {
            TryDelete(cachePath);
        }

        cancellationToken.ThrowIfCancellationRequested();
        if (!PngCodec.TryEncodeWithAdaptiveFilters(decoded, out byte[]? candidate) ||
            candidate is null ||
            candidate.Length >= original.Length ||
            !PngCodec.IsPixelEquivalent(decoded, candidate))
        {
            return new(original, false, false);
        }

        TryWriteCache(cachePath, candidate);
        return new(candidate, true, false);
    }

    private byte[]? TryReadCache(string path)
    {
        try
        {
            lock (_cacheLock)
            {
                return File.Exists(path) ? File.ReadAllBytes(path) : null;
            }
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            return null;
        }
    }

    private void TryWriteCache(string path, byte[] bytes)
    {
        try
        {
            lock (_cacheLock)
            {
                Directory.CreateDirectory(_cacheRoot);
                string temporary = Path.Combine(_cacheRoot, $".{Guid.NewGuid():N}.tmp");
                try
                {
                    File.WriteAllBytes(temporary, bytes);
                    File.Move(temporary, path, overwrite: true);
                }
                finally
                {
                    if (File.Exists(temporary)) File.Delete(temporary);
                }
                PruneCache();
            }
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            // The cache is only a performance aid. Export continues with verified bytes.
        }
    }

    private void PruneCache()
    {
        if (!Directory.Exists(_cacheRoot)) return;
        FileInfo[] files = new DirectoryInfo(_cacheRoot)
            .EnumerateFiles("*.png", SearchOption.TopDirectoryOnly)
            .Where(file => (file.Attributes & FileAttributes.ReparsePoint) == 0)
            .OrderBy(file => file.LastWriteTimeUtc)
            .ToArray();
        long total = files.Sum(file => file.Length);
        foreach (FileInfo file in files)
        {
            if (total <= _maximumCacheBytes) break;
            try
            {
                long length = file.Length;
                file.Delete();
                total -= length;
            }
            catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
            {
            }
        }
    }

    private void TryTouch(string path)
    {
        try
        {
            lock (_cacheLock) File.SetLastWriteTimeUtc(path, DateTime.UtcNow);
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
        }
    }

    private void TryDelete(string path)
    {
        try
        {
            lock (_cacheLock)
            {
                if (File.Exists(path)) File.Delete(path);
            }
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
        }
    }

    private sealed record PngChunk(string Type, byte[] Data);

    private sealed record DecodedPng(
        int Width,
        int Height,
        int BytesPerPixel,
        int RowBytes,
        byte ColorType,
        IReadOnlyList<PngChunk> Chunks,
        byte[] ReconstructedRows);

    private static class PngCodec
    {
        public static bool TryDecode(byte[] bytes, out DecodedPng? decoded)
        {
            decoded = null;
            try
            {
                if (bytes.Length < Signature.Length || !bytes.AsSpan(0, 8).SequenceEqual(Signature))
                {
                    return false;
                }

                var chunks = new List<PngChunk>();
                using var idat = new MemoryStream();
                int offset = 8;
                while (offset <= bytes.Length - 12)
                {
                    uint lengthValue = BinaryPrimitives.ReadUInt32BigEndian(bytes.AsSpan(offset, 4));
                    if (lengthValue > int.MaxValue) return false;
                    int length = (int)lengthValue;
                    int chunkEnd = checked(offset + 12 + length);
                    if (chunkEnd > bytes.Length) return false;
                    string type = Encoding.ASCII.GetString(bytes, offset + 4, 4);
                    byte[] typeBytes = bytes.AsSpan(offset + 4, 4).ToArray();
                    byte[] data = bytes.AsSpan(offset + 8, length).ToArray();
                    uint storedCrc = BinaryPrimitives.ReadUInt32BigEndian(
                        bytes.AsSpan(offset + 8 + length, 4));
                    if (storedCrc != Crc32(typeBytes, data)) return false;
                    chunks.Add(new(type, data));
                    if (type == "IDAT") idat.Write(data);
                    offset = chunkEnd;
                    if (type == "IEND") break;
                }

                PngChunk? header = chunks.FirstOrDefault(chunk => chunk.Type == "IHDR");
                if (header is null || header.Data.Length != 13 || idat.Length == 0) return false;
                int width = checked((int)BinaryPrimitives.ReadUInt32BigEndian(header.Data.AsSpan(0, 4)));
                int height = checked((int)BinaryPrimitives.ReadUInt32BigEndian(header.Data.AsSpan(4, 4)));
                byte bitDepth = header.Data[8];
                byte colorType = header.Data[9];
                if (width <= 0 || height <= 0 || bitDepth != 8 ||
                    header.Data[10] != 0 || header.Data[11] != 0 || header.Data[12] != 0)
                {
                    return false;
                }
                int bytesPerPixel = colorType switch
                {
                    0 => 1,
                    2 => 3,
                    3 => 1,
                    4 => 2,
                    6 => 4,
                    _ => 0,
                };
                if (bytesPerPixel == 0) return false;
                int rowBytes = checked(width * bytesPerPixel);
                idat.Position = 0;
                byte[] rows = new byte[checked(height * rowBytes)];
                using (var zlib = new ZLibStream(idat, CompressionMode.Decompress, leaveOpen: true))
                {
                    for (int y = 0; y < height; y++)
                    {
                        int filterValue = zlib.ReadByte();
                        if (filterValue is < 0 or > 4) return false;
                        byte filter = (byte)filterValue;
                        int rowOffset = y * rowBytes;
                        zlib.ReadExactly(rows.AsSpan(rowOffset, rowBytes));
                        for (int x = 0; x < rowBytes; x++)
                        {
                            byte source = rows[rowOffset + x];
                            byte left = x >= bytesPerPixel ? rows[rowOffset + x - bytesPerPixel] : (byte)0;
                            byte up = y > 0 ? rows[rowOffset - rowBytes + x] : (byte)0;
                            byte upperLeft = y > 0 && x >= bytesPerPixel
                                ? rows[rowOffset - rowBytes + x - bytesPerPixel]
                                : (byte)0;
                            int predictor = filter switch
                            {
                                0 => 0,
                                1 => left,
                                2 => up,
                                3 => (left + up) / 2,
                                4 => Paeth(left, up, upperLeft),
                                _ => 0,
                            };
                            rows[rowOffset + x] = unchecked((byte)(source + predictor));
                        }
                    }
                    if (zlib.ReadByte() != -1) return false;
                }

                if (colorType == 3)
                {
                    byte[]? palette = chunks.FirstOrDefault(chunk => chunk.Type == "PLTE")?.Data;
                    if (palette is null || palette.Length == 0 || palette.Length % 3 != 0 ||
                        rows.Any(index => index >= palette.Length / 3))
                    {
                        return false;
                    }
                }
                decoded = new(width, height, bytesPerPixel, rowBytes, colorType, chunks, rows);
                return true;
            }
            catch (Exception exception) when (
                exception is InvalidDataException or IOException or OverflowException or ArgumentException)
            {
                return false;
            }
        }

        public static bool TryEncodeWithAdaptiveFilters(DecodedPng decoded, out byte[]? encoded)
        {
            encoded = null;
            try
            {
                byte[] candidate = new byte[decoded.RowBytes];
                byte[] best = new byte[decoded.RowBytes];
                byte[] compressed;
                using (var compressedStream = new MemoryStream())
                {
                    using (var zlib = new ZLibStream(
                        compressedStream,
                        CompressionLevel.SmallestSize,
                        leaveOpen: true))
                    {
                        for (int y = 0; y < decoded.Height; y++)
                        {
                            long bestScore = long.MaxValue;
                            byte bestFilter = 0;
                            int rowOffset = y * decoded.RowBytes;
                            for (byte filter = 0; filter <= 4; filter++)
                            {
                                long score = 0;
                                for (int x = 0; x < decoded.RowBytes; x++)
                                {
                                    byte value = decoded.ReconstructedRows[rowOffset + x];
                                    byte left = x >= decoded.BytesPerPixel
                                        ? decoded.ReconstructedRows[rowOffset + x - decoded.BytesPerPixel]
                                        : (byte)0;
                                    byte up = y > 0
                                        ? decoded.ReconstructedRows[rowOffset - decoded.RowBytes + x]
                                        : (byte)0;
                                    byte upperLeft = y > 0 && x >= decoded.BytesPerPixel
                                        ? decoded.ReconstructedRows[rowOffset - decoded.RowBytes + x - decoded.BytesPerPixel]
                                        : (byte)0;
                                    int predictor = filter switch
                                    {
                                        0 => 0,
                                        1 => left,
                                        2 => up,
                                        3 => (left + up) / 2,
                                        4 => Paeth(left, up, upperLeft),
                                        _ => 0,
                                    };
                                    byte result = unchecked((byte)(value - predictor));
                                    candidate[x] = result;
                                    score += result < 128 ? result : 256 - result;
                                }
                                if (score < bestScore)
                                {
                                    bestScore = score;
                                    bestFilter = filter;
                                    candidate.CopyTo(best, 0);
                                }
                            }
                            zlib.WriteByte(bestFilter);
                            zlib.Write(best);
                        }
                    }
                    compressed = compressedStream.ToArray();
                }

                using var output = new MemoryStream();
                output.Write(Signature);
                bool wroteIdat = false;
                foreach (PngChunk chunk in decoded.Chunks)
                {
                    if (chunk.Type == "IDAT")
                    {
                        if (!wroteIdat)
                        {
                            WriteChunk(output, "IDAT", compressed);
                            wroteIdat = true;
                        }
                        continue;
                    }
                    WriteChunk(output, chunk.Type, chunk.Data);
                }
                if (!wroteIdat) return false;
                encoded = output.ToArray();
                return true;
            }
            catch (Exception exception) when (
                exception is InvalidDataException or IOException or OverflowException or ArgumentException)
            {
                return false;
            }
        }

        public static bool IsPixelEquivalent(DecodedPng original, byte[] candidate) =>
            TryDecode(candidate, out DecodedPng? decoded) && decoded is not null &&
            decoded.Width == original.Width &&
            decoded.Height == original.Height &&
            decoded.ColorType == original.ColorType &&
            decoded.ReconstructedRows.AsSpan().SequenceEqual(original.ReconstructedRows) &&
            NonImageDataChunksEqual(original.Chunks, decoded.Chunks);

        private static bool NonImageDataChunksEqual(
            IReadOnlyList<PngChunk> left,
            IReadOnlyList<PngChunk> right)
        {
            PngChunk[] leftChunks = left.Where(chunk => chunk.Type != "IDAT").ToArray();
            PngChunk[] rightChunks = right.Where(chunk => chunk.Type != "IDAT").ToArray();
            return leftChunks.Length == rightChunks.Length && leftChunks
                .Zip(rightChunks)
                .All(pair => pair.First.Type == pair.Second.Type &&
                    pair.First.Data.AsSpan().SequenceEqual(pair.Second.Data));
        }

        private static int Paeth(int left, int up, int upperLeft)
        {
            int estimate = left + up - upperLeft;
            int leftDistance = Math.Abs(estimate - left);
            int upDistance = Math.Abs(estimate - up);
            int upperLeftDistance = Math.Abs(estimate - upperLeft);
            return leftDistance <= upDistance && leftDistance <= upperLeftDistance
                ? left
                : upDistance <= upperLeftDistance ? up : upperLeft;
        }

        private static void WriteChunk(Stream stream, string type, byte[] data)
        {
            Span<byte> length = stackalloc byte[4];
            BinaryPrimitives.WriteUInt32BigEndian(length, checked((uint)data.Length));
            stream.Write(length);
            byte[] typeBytes = Encoding.ASCII.GetBytes(type);
            stream.Write(typeBytes);
            stream.Write(data);
            Span<byte> crcBytes = stackalloc byte[4];
            BinaryPrimitives.WriteUInt32BigEndian(crcBytes, Crc32(typeBytes, data));
            stream.Write(crcBytes);
        }

        private static uint Crc32(byte[] type, byte[] data)
        {
            uint crc = uint.MaxValue;
            foreach (byte value in type) crc = UpdateCrc(crc, value);
            foreach (byte value in data) crc = UpdateCrc(crc, value);
            return ~crc;
        }

        private static uint UpdateCrc(uint crc, byte value)
        {
            crc ^= value;
            for (int index = 0; index < 8; index++)
            {
                crc = (crc & 1) != 0 ? 0xEDB88320u ^ (crc >> 1) : crc >> 1;
            }
            return crc;
        }
    }
}
