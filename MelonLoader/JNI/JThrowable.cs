#if ANDROID
namespace MelonLoader.Java;

public class JThrowable : JObject
{
    public JThrowable() { }

    public string GetMessage()
    {
        using var type = JNI.FindClass("java/lang/Throwable");
        using var value = type.CallObjectMethod<JString>(this, "getMessage", "()Ljava/lang/String;");
        return value.IsNull ? "" : value.GetString();
    }

    public override string ToString()
    {
        using var type = JNI.FindClass("java/lang/Throwable");
        using var value = type.CallObjectMethod<JString>(this, "toString", "()Ljava/lang/String;");
        return value.IsNull ? "" : value.GetString();
    }
}
#endif
