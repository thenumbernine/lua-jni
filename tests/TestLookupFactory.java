import java.lang.invoke.MethodHandles;
public class TestLookupFactory {
    public static MethodHandles.Lookup getFullAccess() {
        return MethodHandles.lookup(); // Has full privilege in this class
    }
}
