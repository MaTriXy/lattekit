package io.lattekit.transformer
import io.lattekit.evaluator.Evaluator
import io.lattekit.parser.*
import io.lattekit.template.KotlinTemplate
import org.antlr.v4.runtime.ANTLRInputStream
import org.antlr.v4.runtime.CommonTokenStream
import org.antlr.v4.runtime.tree.TerminalNode

/**
 * Created by maan on 4/1/16.
 */
class TransformOutput {
    var packageName : String? = null;
    var imports = mutableSetOf("io.lattekit.Latte")
    var resourceIds = mutableListOf<String>();
    var classes = mutableListOf<TransformedClass>();
}

class TransformedClass {
    var className : String? = null;
    var output : String ? = null;
    var containsLayout = false;
}

class KotlinTransformer2(var androidPackageId: String) {
    var resourceIds = mutableListOf<String>()
    fun transform( source : String ) :  LatteFile {
        var parsed = KotlinParser().parseSource(source)
        Evaluator(androidPackageId).evaluate(parsed);
        var template = KotlinTemplate()
        parsed.classes.forEach {
            it.generatedSource = template.renderClass(it, parsed).toString()
        }
        resourceIds.addAll(parsed.resourceIds)
        return parsed;

    }
}
class KotlinTransformer(androidPackageId: String) : LatteBaseVisitor<String>() {

    var packageName : String? = null;
    var applicationId : String? = androidPackageId;
    var imports = mutableSetOf("io.lattekit.view.*","io.lattekit.Latte")
    var resourceIds = mutableListOf<String>();

    var ANDROID_RES_RE = Regex("""@(?:([^:\/]+):)?\+?([^:\/]+)\/(.*)""")
    val CLASS_NAME_RE = Regex(""".*class\s+([^ :]+).*""")

    fun transformUnit(ctx: LatteParser.UnitContext): TransformOutput {
        var output = TransformOutput();

        // Find package name
        var packageDeclaration = ctx.packageDeclaration()?.firstOrNull();
        if (packageDeclaration != null) {
            packageName = packageDeclaration.text.split(" ").last()
        }
        imports = mutableSetOf("io.lattekit.view.*","io.lattekit.Latte")
        // Find imports name
        ctx.importStatement()?.forEach {
            imports.add(it.text.split(" ").last());
        }
        output.packageName = packageName;
        output.imports = imports;

        ctx.classDeclaration().forEach {
            var transformedCls = transformLayoutClass(it);
            if (transformedCls.containsLayout) {
                output.classes.add(transformedCls);
            }
        }
        output.resourceIds = resourceIds;
        return output;
    }
    fun transformLayoutClass(ctx : LatteParser.ClassDeclarationContext) : TransformedClass {
        var transformedClass = TransformedClass();
        var output = StringBuilder();
        var clsName = CLASS_NAME_RE.matchEntire(ctx.LAYOUT_CLASS().text)!!.groupValues[1]
        transformedClass.className = clsName+"Impl";
        output.append("""package $packageName;

${imports.map {"import $it"}.joinToString("\n")}

class ${clsName}Impl : $clsName() {
        """)
        if (ctx.classBody().layoutFunction().size > 0) {
            transformedClass.containsLayout = true;
        }
        ctx.classBody().layoutFunction().forEach {
            var funWords = if (it.LAYOUT_FUN() != null) {
                it.LAYOUT_FUN()
            } else {
                it.LAYOUT_FUN_BLOCK()
            }.text.replace(Regex("\\s+")," ").split(" ");
            var keywords = mutableListOf<String>()
            var funName = funWords.find { if (!it.contains("(")) { keywords.add(it); false } else true; }

            output.append("""
    ${keywords.joinToString(" ")} ${funName} {
        ${visitLayoutString(it.layoutString())}
    }""")
        }
        output.append("\n}")
        transformedClass.output = output.toString()
        return transformedClass;
    }

    override fun visitLayoutString(ctx: LatteParser.LayoutStringContext): String {
        var result = "";
        ctx.layoutBody().children.forEach {
            if (it is LatteParser.InlineCodeContext) {
                result += "\${" + visitInlineCode(it) + "}\n"
            } else if (it is LatteParser.XmlTagContext) {
                result += "\n"+visitXmlTag(it)
            } else {
                result += it.text
            }
            visit(it);
        }

        return result;
    }

    override fun visitInlineCode(ctx: LatteParser.InlineCodeContext): String {
        return visitInlineCodeContent(ctx.inlineCodeContent());
    }

    override fun visitInlineCodeContent(ctx: LatteParser.InlineCodeContentContext): String {
        var output = "";
        ctx.children.forEach {
            output += visit(it);
        }
        return output;
    }
    override fun visitCodeBase(ctx: LatteParser.CodeBaseContext): String? {
        if (ctx.layoutString() != null) return visitLayoutString(ctx.layoutString())
        else return ctx.text
    }
    override fun visitXmlTag(ctx: LatteParser.XmlTagContext): String {
        var clsName = ctx.XML_TAG_OPEN().text.substring(1);
        var clz = Reflection.lookupClass(clsName)
        if (clz != null) {
            return visitXmlTagNative(ctx, clz)
        }

        var output = """
            __current.addChild(Latte.create(Latte.lookupClass("${clsName}"), mutableMapOf(${ctx.layoutProp().map {visit(it)}.joinToString(",")}), mutableMapOf(), { it : LatteView ->
                ${ if (ctx.layoutBody() != null) ctx.layoutBody()?.children?.map { "\n__current = __it\n"  + visit(it)  }?.joinToString("") else ""}
            }))
        """

        return output.toString()
    }

    fun visitXmlTagNative( ctx : LatteParser.XmlTagContext, clz : Class<*>) : String {
        var output = """
        __current.addChild(Latte.createNative(${clz.name}::class.java, mutableMapOf(${ctx.layoutProp().map {visit(it)}.joinToString(",")}),  mutableMapOf(), { __viewWrapper, __lprops ->
            var __view = __viewWrapper.androidView as ${clz.name};
            var __acceptedProps = mutableListOf<String>();
            __lprops.forEach {
                var __propKey = it.key;
                var __propValue = it.value;
                ${ctx.layoutProp().map{
                    getPropValueSetter(it, clz)
                }.joinToString("\n")}
            }
            __acceptedProps
        }, { __it : LatteView ->
            ${ if (ctx.layoutBody() != null) ctx.layoutBody()?.children?.map { "\n__current = __it\n"  + visit(it)  }?.joinToString("") else ""}
        }))
        """
        return output
    }
    fun getTypeName( type : Class<*>, addOptional: Boolean ) : String{
        if (type.name == "java.lang.CharSequence") {
            return "String"+(if (addOptional) "?" else "")
        } else if (type.isPrimitive) {
            return type.name.substring(0,1).toUpperCase() + type.name.substring(1)
        } else {
            return type.name.replace(Regex("\\$"),".")+(if (addOptional) "?" else "")
        }
    }

    fun getPropValueSetter(ctx: LatteParser.LayoutPropContext, clz : Class<*>) : String {
        var propName = ctx.propName().text

        var field = if (propName.startsWith("@")) {
            propName.substring(1)
        } else propName;

        val setter = "set" + field.substring(0, 1).toUpperCase() + field.substring(1)
        var methods = Reflection.findMethods(clz, setter);

        val getterMethods = Reflection.findGetterMethods(clz, "get" + field.substring(0, 1).toUpperCase() + field.substring(1)) + Reflection.findGetterMethods(clz, "is" + field.substring(0, 1).toUpperCase() + field.substring(1));

        val isFn = if (methods.isEmpty()) {
            methods = Reflection.findMethods(clz, setter+"Listener");
            true
        } else { false }
        if (methods.isEmpty() || setter == "setOnClick" || setter == "setOnTouch") {
            return "";
        }
        return """if (__propKey == "${propName}") {
        """ + methods.map {"""
        if (__propValue is ${if (isFn)"Function<*>" else getTypeName(it.parameters.get(0).type,true)}${if (getTypeName(it.parameters.get(0).type,false) == "String") "|| __propValue is CharSequence?" else ""} ${ if (getTypeName(it.parameters.get(0).type,false) == "Boolean") """|| __propValue == "true" || __propValue == "false"""" else ""}) {
            ${if (isFn) """
            var __listener = io.lattekit.Latte.createLambdaProxyInstance(${getTypeName(it.parameters.get(0).type,false)}::class.java, __propValue as Object) as ${getTypeName(it.parameters.get(0).type,true)}
            __view.${setter}${if (isFn) "Listener" else ""}(__listener);
            """ else """
            ${if (!getterMethods.isEmpty() && (getterMethods.get(0).returnType.isAssignableFrom(it.parameters.get(0).type) || (it.parameters.get(0).type.isAssignableFrom(getterMethods.get(0).returnType)))) """
                var __currentValue = if (__view.${getterMethods.get(0).name}() == null) null else __view.${getterMethods.get(0).name}()${if (getterMethods.get(0).returnType.simpleName == "CharSequence") ".toString()" else ""};
                if (__currentValue != __propValue) {
                    ${if (getTypeName(it.parameters.get(0).type,false) == "String") """
                    if (__propValue is CharSequence?) {
                        __view.${setter}((__propValue as CharSequence?)?.toString());
                    } else {
                        __view.${setter}(__propValue as ${getTypeName(it.parameters.get(0).type,true)});
                    }
                    """ else if (getTypeName(it.parameters.get(0).type,false) == "Boolean") """
                    if (__propValue == "true") {
                        __view.${setter}(true);
                    } else if (__propValue == "false") {
                        __view.${setter}(false);
                    } else {
                        __view.${setter}(__propValue as ${getTypeName(it.parameters.get(0).type,true)} as Boolean);
                    }
                    """ else """
                    __view.${setter}(__propValue as ${getTypeName(it.parameters.get(0).type,true)});
                    """}
                }""" else """
                ${if (getTypeName(it.parameters.get(0).type,false) == "String") """
                if (__propValue is CharSequence?) {
                    __view.${setter}((__propValue as CharSequence?)?.toString());
                } else {
                    __view.${setter}(__propValue as ${getTypeName(it.parameters.get(0).type,true)});
                }
                """ else if (getTypeName(it.parameters.get(0).type,false) == "Boolean") """
                if (__propValue == "true") {
                    __view.${setter}(true);
                } else if (__propValue == "false") {
                    __view.${setter}(false);
                } else {
                    __view.${setter}(__propValue as ${getTypeName(it.parameters.get(0).type,true)} as Boolean);
                }
                """ else """
                __view.${setter}(__propValue as ${getTypeName(it.parameters.get(0).type,true)});
                """}
                """}
            """}
            __acceptedProps.add("${propName}");
        }
        """}.joinToString("else ") +"}"
    }
    override fun visitLayoutProp(ctx: LatteParser.LayoutPropContext): String {
        var output = "";
        var propName = ctx.propName().text
        var field = if (propName.startsWith("@")) {
            propName.substring(1)
        } else propName;
        var value = if (ctx.inlineCode() != null) {
            "("+visitInlineCode(ctx.inlineCode())+")"
        } else {
            var stringLiteral = ctx.STRING_LITERAL().text;
            var stringValue = stringLiteral.substring(1,stringLiteral.length-1)
            var matcher = ANDROID_RES_RE.matchEntire(stringValue)
            if(matcher != null) {
                val resPackageName = if(matcher.groupValues.getOrNull(1) != null && matcher.groupValues[1] != "") {
                    matcher.groupValues[1]
                } else { applicationId }
                if(matcher.groupValues.getOrNull(2) == "id" && resPackageName == applicationId) {
                    resourceIds.add(matcher.groupValues[3])
                }
                """${resPackageName}.R.${matcher.groupValues[2]}.${matcher.groupValues[3]}"""
            } else {
                stringLiteral
            }
        }
        output += """"$propName" to $value""";
        return output;
    }

    override fun visitCodeChar(ctx: LatteParser.CodeCharContext): String = ctx.text
    override fun visitTerminal(node: TerminalNode): String = node.text
    fun transform(source : String) : TransformOutput {
        var inputStream = ANTLRInputStream(source);
        var lexer = LatteLexer(inputStream);
        var tokens = CommonTokenStream(lexer);
        var parser = LatteParser(tokens)
        var tree = parser.unit(); // begin parsing at query rule

        var result = transformUnit(tree)
        return result;
    }

}

val DOLLAR = "$";
val MQ = "\"\"\"";

fun main(args : Array<String>) {
    Reflection.loadAndroidSdk("/Users/maan/Library/Android/sdk","android-23");
    println ("X:" + KotlinTransformer("mobi.yummyfood.android").transform("""
package mobi.yummyfood.android

open class MyApp : LatteView() {

    override fun layout() = lxml($MQ
        <ListView data=$DOLLAR{data} id="@+id/hello" layout_width="match_parent" layout_height="match_parent" dividerHeight={0}>
            <mobi.yummyfood.android.FoodItem defaultView="true" />
        </ListView>
    $MQ)
}



    """).classes.map { it.output }.joinToString { "\n" })
}
