import java.util.List;
import java.util.function.Function;
import java.util.function.Supplier;

public class A extends Base {
    public List<String> lambdaForm(List<Object> in) {
        return in.stream().map(item -> Widget.makeFn(item)).toList();
    }

    public List<String> typeMethod(List<Object> in) {
        return in.stream().map(Widget::makeFn).toList();
    }

    public List<String> nestedTypeMethod(List<Object> in) {
        return in.stream().map(Outer.Inner::makeFn).toList();
    }

    public List<String> genericTypeMethod(List<Object> in) {
        return in.stream().map(Widget::<Object>makeFn).toList();
    }

    public Function<Object, String> instanceMethod(Widget widget) {
        return widget::instanceFn;
    }

    public Function<Object, String> instanceSameName(Widget widget) {
        return widget::makeFn;
    }

    public Function<Object, String> shadowedTypeName(Widget Widget) {
        return Widget::instanceFn;
    }

    public Function<Object, String> localShadowedTypeName() {
        Widget Widget = null;
        return Widget::localShadowFn;
    }

    public Function<Object, String> thisMethod() {
        return this::thisFn;
    }

    public Function<Object, String> thisSameName() {
        return this::makeFn;
    }

    public Function<Object, String> superMethod() {
        return super::superFn;
    }

    public Function<Object, String> superSameName() {
        return super::makeFn;
    }

    public Supplier<Widget> typeNew() {
        return Widget::new;
    }

    public String makeFn(Object value) { return String.valueOf(value); }
    public String thisFn(Object value) { return String.valueOf(value); }
}

class Base {
    public String makeFn(Object value) { return String.valueOf(value); }
    public String superFn(Object value) { return String.valueOf(value); }
}

class FieldShadowHost {
    Widget Widget;
    public Function<Object, String> fieldShadowedTypeName() {
        return Widget::fieldShadowFn;
    }
}
