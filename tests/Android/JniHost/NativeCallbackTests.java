import org.lemonloader.interop.NativeCallback;

public final class NativeCallbackTests {
    public interface OverloadedEquals {
        int equals(String value);
        boolean equals(Object value);
        int hashCode();
        String toString();
    }
    public static void main(String[] arguments) throws Exception {
        NativeCallback helper = new NativeCallback(1);
        try {
            helper.proxy(OverloadedEquals.class.getName(), new String[0]);
            throw new AssertionError("Missing equals overload accepted.");
        } catch (IllegalArgumentException expected) { }
        OverloadedEquals proxy = (OverloadedEquals)helper.proxy(OverloadedEquals.class.getName(),
            new String[] { "equals.(Ljava/lang/String;)I" });
        if (!proxy.equals((Object)proxy) || proxy.equals(new Object()) ||
            proxy.hashCode() != System.identityHashCode(proxy) || !proxy.toString().contains("callback 1"))
            throw new AssertionError("Object identity methods changed.");
        try {
            proxy.equals("overload");
            throw new AssertionError("equals(String) was intercepted as Object.equals.");
        } catch (UnsatisfiedLinkError expected) {
            // The host fixture deliberately has no native registration. Reaching
            // invoke proves that the overload goes through callback dispatch.
            if (!expected.getMessage().contains("NativeCallback.invoke")) throw expected;
        }
        System.out.println("PASS exact proxy Object methods/equals overload");
    }
}
