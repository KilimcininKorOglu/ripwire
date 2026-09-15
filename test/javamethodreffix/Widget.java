public class Widget {
    public Widget() {}
    public static String makeFn(Object value) { return String.valueOf(value); }
    public String instanceFn(Object value) { return String.valueOf(value); }
    public String localShadowFn(Object value) { return String.valueOf(value); }
    public String fieldShadowFn(Object value) { return String.valueOf(value); }
}
