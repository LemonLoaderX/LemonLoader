using System.Text;
using AssetsTools.NET;
using AssetsTools.NET.Extra;

static class Fixtures
{
    internal static byte[] Managers()
    {
        var strings = new List<byte>();
        uint Text(string text) { uint offset = (uint)strings.Count; strings.AddRange(Encoding.UTF8.GetBytes(text)); strings.Add(0); return offset; }
        var nodes = new List<TypeTreeNode>
        {
            new() { Version = 1, Level = 0, TypeStrOffset = Text("PlayerSettings"), NameStrOffset = Text("Base"), ByteSize = -1 }
        };
        foreach (string field in new[] { "bundleVersion", "companyName", "productName" })
        {
            nodes.Add(new TypeTreeNode { Version = 1, Level = 1, TypeStrOffset = Text("string"), NameStrOffset = Text(field), ByteSize = -1, Index = (uint)nodes.Count, MetaFlags = 0x4000 });
            nodes.Add(new TypeTreeNode { Version = 1, Level = 2, TypeStrOffset = Text("Array"), NameStrOffset = Text("Array"), ByteSize = -1, Index = (uint)nodes.Count, TypeFlags = (TypeTreeNodeFlags)1, MetaFlags = 0x4000 });
            nodes.Add(new TypeTreeNode { Version = 1, Level = 3, TypeStrOffset = Text("int"), NameStrOffset = Text("size"), ByteSize = 4, Index = (uint)nodes.Count });
            nodes.Add(new TypeTreeNode { Version = 1, Level = 3, TypeStrOffset = Text("char"), NameStrOffset = Text("data"), ByteSize = 1, Index = (uint)nodes.Count });
        }
        var type = new TypeTreeType
        {
            TypeId = (int)AssetClassID.PlayerSettings, ScriptTypeIndex = ushort.MaxValue,
            TypeHash = new Hash128(new byte[16]), ScriptIdHash = new Hash128(new byte[16]),
            Nodes = nodes, StringBufferBytes = strings.ToArray(), TypeDependencies = []
        };
        var info = new AssetFileInfo { PathId = 1, TypeId = (int)AssetClassID.PlayerSettings, TypeIdOrIndex = 0 };
        using var data = new MemoryStream();
        using (var writer = new BinaryWriter(data, Encoding.UTF8, true))
            foreach (string value in new[] { "1.2.3", "Fixture Studio", "Fixture Game" })
            {
                byte[] utf8 = Encoding.UTF8.GetBytes(value);
                writer.Write(utf8.Length); writer.Write(utf8);
                while (data.Position % 4 != 0) writer.Write((byte)0);
            }
        info.SetNewData(data.ToArray());
        using var empty = new MemoryStream();
        var file = new AssetsFile
        {
            Header = new AssetsFileHeader { Version = 17, Endianness = false },
            Metadata = new AssetsFileMetadata
            {
                UnityVersion = "2021.3.0f1", TargetPlatform = 13, TypeTreeEnabled = true,
                TypeTreeTypes = [type], AssetInfos = new List<AssetFileInfo> { info },
                ScriptTypes = [], Externals = [], RefTypes = [], UserInformation = ""
            },
            Reader = new AssetsFileReader(empty)
        };
        using var output = new MemoryStream();
        using (var writer = new AssetsFileWriter(output)) file.Write(writer);
        return output.ToArray();
    }

    internal static byte[] Bundle(byte[] managers, string name = "globalgamemanagers")
    {
        var entry = AssetBundleDirectoryInfo.Create(name, true);
        entry.SetNewData(managers);
        using var empty = new MemoryStream();
        var bundle = new AssetBundleFile
        {
            Header = new AssetBundleHeader
            {
                Signature = "UnityFS", Version = 6, GenerationVersion = "5.x.x",
                EngineVersion = "2021.3.0f1",
                FileStreamHeader = new AssetBundleFSHeader { Flags = (AssetBundleFSHeaderFlags)0x40 }
            },
            BlockAndDirInfo = new AssetBundleBlockAndDirInfo { Hash = new Hash128(new byte[16]), BlockInfos = [], DirectoryInfos = [entry] },
            Reader = new AssetsFileReader(empty),
            DataReader = new AssetsFileReader(empty)
        };
        using var output = new MemoryStream();
        using (var writer = new AssetsFileWriter(output)) bundle.Write(writer);
        return output.ToArray();
    }
}
