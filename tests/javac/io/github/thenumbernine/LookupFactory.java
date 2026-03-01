package io.github.thenumbernine;
import java.lang.invoke.MethodHandles;
public class LookupFactory {
    public static MethodHandles.Lookup getFullAccess() {
        return MethodHandles.lookup();
    }
}
