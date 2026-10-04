package org.lemonloader.interop;

import java.lang.reflect.InvocationHandler;
import java.lang.reflect.Method;
import java.lang.reflect.Proxy;

public final class NativeCallback implements Runnable, InvocationHandler {
    private final long token;
    private static final Object[] EMPTY = new Object[0];
    public NativeCallback(long token) { this.token = token; }
    private static native Object invoke(long token, String member, Object[] arguments);
    public void run() { invoke(token, "run.()V", EMPTY); }
    public Object proxy(String name, String[] members) throws ClassNotFoundException {
        ClassLoader loader = getClass().getClassLoader();
        Class<?> type = Class.forName(name.replace('/', '.'), false, loader);
        if (!type.isInterface()) throw new IllegalArgumentException("Callback target must be an interface.");
        for (Method method : type.getMethods()) {
            if (!java.lang.reflect.Modifier.isAbstract(method.getModifiers()) || method.getDeclaringClass() == Object.class) continue;
            if (isObjectMethod(member(method))) continue;
            String required = member(method);
            boolean found = false;
            for (String supplied : members) if (required.equals(supplied)) { found = true; break; }
            if (!found) throw new IllegalArgumentException("Missing callback " + required);
        }
        return Proxy.newProxyInstance(loader, new Class<?>[] { type }, this);
    }
    @Override public Object invoke(Object proxy, Method method, Object[] args) {
        String name = member(method);
        if (name.equals("equals.(Ljava/lang/Object;)Z")) return proxy == args[0];
        if (name.equals("hashCode.()I")) return System.identityHashCode(proxy);
        if (name.equals("toString.()Ljava/lang/String;")) return "LemonLoader callback " + token;
        return invoke(token, name, args == null ? EMPTY : args);
    }
    private static boolean isObjectMethod(String member) {
        return member.equals("equals.(Ljava/lang/Object;)Z") || member.equals("hashCode.()I") || member.equals("toString.()Ljava/lang/String;");
    }
    private static String member(Method method) {
        StringBuilder signature = new StringBuilder(method.getName()).append(".(");
        for (Class<?> type : method.getParameterTypes()) signature.append(descriptor(type));
        signature.append(')').append(descriptor(method.getReturnType()));
        return signature.toString();
    }
    private static String descriptor(Class<?> type) {
        if (type.isArray()) return type.getName().replace('.', '/');
        if (!type.isPrimitive()) return "L" + type.getName().replace('.', '/') + ";";
        if (type == void.class) return "V";
        if (type == boolean.class) return "Z";
        if (type == byte.class) return "B";
        if (type == char.class) return "C";
        if (type == short.class) return "S";
        if (type == int.class) return "I";
        if (type == long.class) return "J";
        if (type == float.class) return "F";
        return "D";
    }
}
