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

    public Function<Object, String> localDeclaredAfter() {
        Function<Object, String> ref = Widget::afterLocalFn;
        Widget Widget = null;
        return ref;
    }

    public Function<Object, String> siblingBlockLocal() {
        if (true) {
            Widget Widget = null;
        }
        return Widget::siblingFn;
    }

    public List<String> packageQualified(List<Object> in) {
        return in.stream().map(com.example.Widget::pkgFn).toList();
    }

    public List<String> nestedInnerLocal(List<Object> in) {
        Object Inner = null;
        return in.stream().map(Outer.Inner::nestedInnerFn).toList();
    }

    public List<String> nestedLeadingShadow(List<Object> in) {
        Outer Outer = null;
        return in.stream().map(Outer.Inner::leadingShadowFn).toList();
    }

    public Function<Object, String> inferredLambdaParam() {
        Function<Object, String> ignore = Widget -> Widget::lambdaInfFn;
        return ignore;
    }

    public Function<Object, String> inferredParenLambdaParam() {
        Function<Object, String> ignore = (Widget) -> Widget::lambdaParenFn;
        return ignore;
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

    // The member the proven type does NOT declare: nestedInnerFn is Outer.Inner's. The receiver is
    // the whole evidence a method reference carries, so this resolves to nothing — it must never
    // fall back to the bare name and steal Outer.Inner's definition.
    public Function<Object, String> typeMissingMember() {
        return Widget::nestedInnerFn;
    }

    // The issue's own pair, the two spellings of one call: the lambda and the method reference must
    // agree on Util.conv.
    public List<String> convLambda(List<Object> in) {
        return in.stream().map(item -> Util.conv(item)).toList();
    }

    public List<String> convMethodRef(List<Object> in) {
        return in.stream().map(Util::conv).toList();
    }

    // r9 shadow-suppression control: `name` is a parameter here AND a method on Builder. Java has no
    // callable locals, so this call can only mean Builder.name — the edge and the --uses row stay.
    public String builderChain(Builder b, String name) {
        return b.name(name).build();
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
