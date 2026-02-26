# Java in LuaJIT

I'm sure this has been done before, but here's my version.

# Quick Start:

`J = require 'java'`

This creates a JVM and return its `JNIEnv` as `J`.

For more control of your initialization:
```
local JVM = require 'java.vm'
local jvm = JVM{
	version = <pick a version>,
	props = {
		['java.class.path'] = <provide a classpath string>,
		['java.library.path'] = <etc>,
		...
	},
}
local J = jvm.jniEnv
```

# Reference

### JVM
`JVM = require 'java.vm'`

- `jvm = JVM(args)` = creates a new VM
- args:
- - `version` = specify which version, defaults to `JNI_VERSION_1_6`
- - and:
- - `ptr` = specify a previously created `JavaVM*` pointer to create this `JavaVM` Lua object, retrieve its `JNIEnv*` JNI C pointer, and create a `JNIEnv` Lua object to go with it.
- - or:
- - `props` = specify additional key/value properties that use the `-D` prefix, i.e. `['java.class.path'] = '.'` builds the opiton `-Djava.class.path=.`.
- - `options` = specify additional key/value properties that use no prefix, i.e. `['--module-path'] = '/usr/share/openjfx/lib'` builds the option `--module-path=/usr/share/openjfx/lib`.
- - `optionList` = specify additional option strings in a list.
- - `libjvm` = path to `libjvm.so`.  By default, `$JAVA_HOME/lib/server/libjvm.so` is used.

- - `jvm._ptr` = the `JavaVM*` pointer

- `jvm:destroy()` = clean up the VM

- `J = jvm.jniEnv` = a JNIEnv object


### JNIEnv
`JNIEnv = require 'java.jnienv'`

- `J = JNIEnv(ptr)` = create a JNIEnv object with the specified `JNIEnv*` pointer

- `J._ptr` = the `JNIEnv*` pointer

- `J._classesLoaded` = internal cache of loaded class-wrappers

- `J:_version()` = returns the JNIEnv version, usually a hex number.

- `J:_str(s)`
- - if `s` is a string, returns a JavaObject wrapping a `java.lang.String` of the Lua-string contents of `s` using C API `JNIEnv.NewStringUTF`.
- - if `s` is cdata, does the same but treating it as a memory pointer.
- `J:_str(s, len)`
- - if `s` is a string, converts it to a `jchar[]` array and uses C API `JNIEnv.NewString`
- - if `s` is cdata, treats it as-is using C API `JNIEnv.NewString`
- see `JavaString`

- `J:_new(class, ...)` = create a new JavaObject.  `class` can be either a JavaClass or a classpath string.

- `J:_newArray(javaType, length, [objInit])`
- - creates a Java array using one of the C API `JNIEnv.New*Array` methods.
- - `javaType` can be a primitive string, a classpath string, a ffi ctype of a primitive, or a `JavaClass` object.
- - see `JavaArray`

- `jclass = J:_getObjClass(objPtr)` = returns a `jclass` pointer for a `jobject` pointer.  Wrapper for C API `JNIEnv.GetObjectClass`.

- `classpath, jclass = J:_getObjClassPath(objPtr)` = returns a Lua string of the classpath and `jclass` for the object in `objPtr`.

- `classObj = J:_saveJClassForClassPath(args)` = always creates a new JavaClass object for the `jclass` pointer, and saves it in this env's `_classesLoaded` table for this `classpath`.

- `J:_findClass(classpath)` = look up a Java class using C API `JNIEnv.FindClass`.

- `cl = J:_getClassForJClass(jclass)` = gets the JavaClass Lua object for a jclass JNI pointer.  Either uses cache or creates a new JavaClass.

- `classpath = J:_getJClassClasspath(jclass)` = uses java.lang.Class.getTypeName() to determine the classname of the JNI jclass pointer.

- `J:_exceptionClear()` = clears the exception in JNIEnv via JNIEnv.ExceptionClear.

- `ex = J:_exceptionOccurred()` = if an exception occurred then returns the exception JavaObject.

- `J:_throw(obj)` = throw in the JNI a exception jobject.

- `J:_throwNew(cl)` = throw in the JNI a exception from a new'd jclass.

- `J:_checkExceptions()` = if an exception occurred, throw it as an error.

- `J:_luaToJavaArg(arg, sig)` = convert a Lua object `arg` to a JNI pointer object. Preparation for the JNI API.  `sig` is a Java type to help in conversion, namely when `arg` is a number.
- `J:_luaToJavaArgs(sigIndex, sig, ...)` = convert a vararg of Lua objects to JNI pointer objects.  `sig` is an array used for function signatures, `sigIndex` is the location in that array.

- `J:__index(k)` = if `J` is indexed with any other key then it is assumed to be a namespace lookup.
- - ex: `J.java` retrieves the namespace `java.*`
- - ex: `J.java.lang` retrieves the namespace `java.lang.*`
- - ex: `J.java.lang.String` retrieves the JavaClass `java.lang.String`

I put primitives in the root namespace to map to LuaJIT FFI cdata types.
This way it is consistent that the J.path.to.class matches with whatever the Lua functions expect as input/output.
And this is so that you can more easily cast your data for calling Java functions using `J.int(x), J.char(y), J.double(z)` etc for correct function overload resolution matching.

If you want the actual primitive `java.lang.Class` classes, use `java.lang.Integer.TYPE` etc.

Notice however there is a limitation to this.  JNI defines `jchar` as C `int`, so if you are passing `J.char` as a type for `_newArray` or for an arugment overload, the call resolver can't tell char from int.


### JavaObject
`JavaObject = require 'java.object'`

- `obj = JavaObject(args)` = wrapper for a Java `jobject`
- args:
- - `env` = `JNIEnv`
- - `ptr` = `jobject`
- - `classpath` = string

- `cl = obj:_getClass()` = get class

- `bool = obj:_instanceof(classTo)` = tests if it can cast, returns boolean.

- `castObj = obj:_cast(classTo)` = cast obj to class `classTo`.  Accepts a JavaClass, a string for a classpath, or a cdata of a jclass.

- `obj:_throw()` = throw this object.

- `method = obj:_method(args)` = shorthand for `obj:_getClass():_method(args)`.

- `field = obj:_field(args)` = shorthand

- `str = obj:_javaToString()` = returns a Lua string based on the Java `toString()` method.

- `str = obj:_getDebugStr()` = useful internal string with a few things like the Lua class name, Java classpath, and pointer.

- `for ch in obj:_iter() do ... end` = iterate across elements of a Java object.  Made to be equivalent to `for (element : collection) { ... }`.

- `cl = JavaObject._getLuaClassForClassPath(classpath)` = helper to get the Lua class for the Java classpath.

- `obj = JavaObject._createObjectForClassPath(args)` = helper to create the appropriate Lua wrapper object, with arguments, depending on `args.classpath`.

- `#obj` aka `obj:__len()` 
- - if it is a `java.lang.String` then this returns the Java string length.
- - if tt is an array then this return the length.
- - otherwise it will return the Java field `obj.length` or Java method `obj.length()` depending on which is present.


### JavaClass
`JavaClass = require 'java.class'`
- `JavaClass = JavaObject:subclass()`

- `cl = JavaClass(args)` = `jclass` wrapper
- args:
- - `env` = the `JNIEnv` Lua object
- - `ptr` = the `jclass`
- - `classpath` = the classpath of this class

- `cl:_new(...)` = create a new JavaObject.

- `cl(...)` aka `cl:__call(...)` = shorthand for `cl:_new(...)`

- `cl:_name()` = returns the classpath of the object, using Java's `class.getTypeName()` method.

- `cl:_super()` = returns a JavaClass of the superclass.

- `cl:_throwNew()` = throw a new instance of this class.

- `cl.class` = equivalent of java code `ClassName.class`, i.e. return the JavaObject jobject instance of a `java.lang.Class` that is associated with this jclass.

- `cl:_class()` = the method underlying `cl.class`.

- `cl:_isAssignableFrom(classTo)` = same as testing a class's instance's instanceof the `classTo`.

- `cl._members[name][index]` = either JavaMethod or JavaField of a member with that name.

- `cl:_method(args)` = returns a `JavaMethod` object for a `jmethodID`.
- args:
- - `name` = the method name
- - `sig` = the method signature, a table of classpaths/primitives, the first is the return type.  An empty table defaults to a `void` return type.
- - `nonvirtual` = forwards to `JavaMethod`
- - `isVarArgs` = forwards to `JavaMethod`
- - `isStatic` = set to `true` to retrieve a static method.

- `cl:_field(args)` = returns a `JavaField` object for a `jfieldID`.
- args:
- - `env` = `JNIEnv` object.
- - `ptr` = `jfieldID`.
- - `name` = field name.
- - `sig` = signature string of the field.
- - `isStatic` = true for static fields.


### JavaField
`JavaField = require 'java.field'`

- `field = JavaField(args)` = wrapper for a `jfieldID`.

- `result = field(thisOrClass)` = shorthand for `field:_get(thisOrClass)`
- `field(thisOrClass, value)` = shorthand for `field:_set(thisOrClass, value)`

- `result = field:_get(thisOrClass)` = gets the Java object's field's value, or Java class's static field's value.
- `field:_set(thisOrClass, value)` = sets the Java object's field's value, or Java class's static field's value.


### JavaMethod
`JavaMethod = require 'java.method'`

- `method = JavaMethod(args)` = wrapper for a `jmethodID`.
- args:
- - `env` = `JNIEnv`
- - `ptr` = `jmethodID`
- - `sig` = signature table, first argument is the return type (default `void`), rest are method arguments.
- - `nonvirtual` = whether this method call will be nonvirtual or not.  Useful for `super.whatever` in Java which relies on non-polymorphic explicit class calls.
- - `isVarArgs` = true when `Method.isVarArgs()` is true, means that the call will convert the args into an array before calling. 
- - `isStatic` = whether this method is static or not.

- `result = method(...)` = invoke ` call on the method using C API `JNIEnv.Call*Method`.

- `obj = method:_new(...)` = for constructor methods, calls C API `JNIEnv.NewObject` on this method.


### JavaString
`JavaString = require 'java.string'`
- `JavaString = JavaObject:subclass()`

- `s = JavaString(args)` = inherited from JavaObject.

- `tostring(s)` aka `s:__tostring()` = returns the Java string contents.

- `s:length()` also returns the length.  This isn't by my design.  Java registers the `java.lang.String`'s `.length` as a *method*, not a *field*.


### JavaArray
`JavaArray = require 'java.array'`
- `JavaArray = JavaObject:subclass()`

- `ar = JavaArray(args)` = inherited from JavaObject, and:
- args:
- - `elemClassPath` = classpath of the array element, needed for subequent operations.

- `ar.elemFFIType` = for primitives, LuaJIT FFI ctype of the JNI primitive type.
- `ar.elemFFIType_1` = for primitives, LuaJIT FFI ctype of a 1-length array of the JNI primitive type.
- `ar.elemFFIType_ptr` = for primitives, LuaJIT FFI ctype of a pointer of the JNI primitive type.

- `ar[i]` aka `ar:_get(i)` = get the i'th index of the array
- `ar[i]=v` aka `ar:_set(i, v)` = set the i'th index of the array

<hr>

Also for JNI, JavaClass, and JavaObject (and subclasses JavaString and JavaArray),
the Lua `__index` and `__newindex` works for fields and methods.

Be sure to always use `obj:func(...)` when calling, even if it's calling a static method, even from a Java class, because Lua needs the context of it, be it objects or classes.

<hr>

I made this to go with my [SDL-LuaJIT](https://github.com/thenumbernine/SDLLuaJIT-android) launcher.

The `java.ffi.jni` file is [`lua-include`](https://github.com/thenumbernine/include-lua) run on `jni.h`.

# Examples

`java/tests/println.lua` is a simple `System.out.println` demo.

`java/tests/runnable.lua` shows how to create and run a thin wrapper class in `java/tests/io/github/thenumbernine/NativeRunnable.java` to native code in `java/tests/io_github_thenumbernine_NativeRunnable.c` to run your C (or LuaJIT-cloure) callback.

`java/tests/runnable_mt.lua` shows how to use this to run LuaJIT code on a new Java thread, in conjunction with my [`lua lite thread class`](https://github.com/thenumbernine/lua-thread/blob/master/lite.lua).

`java/tests/applet.lua` shows a simple Swing application demo, though it can't do much without subclassing live or with running installed `javac`.

`java/tests/ffm.lua` uses Java Foreign Function Interface, so I don't need external classes like `io.github.thenumbernine.NativeRunnable` or dependency jars like "ByteBuddy".  Works but sad my Android doesn't support it.

`java/tests/test-java-asm.lua` uses Java-ASM to create classes at runtime to invoke LuaJIT calls, so I don't need external classes (except that last hurdle of loading a class from bytecode within a JNI C app...), but I'd still need external `asm.jar`...

`java/tests/runnable-asm.lua` uses Java-ASM to create a `java.lang.Runnable` subclass at runtime with native `.so` to invoke LuaJIT calls.  It requires no extra Java classes, however it still requires one extra native method compiled in C to forward back to LuaJIT callbacks.

`java/tests/bytebuddy.lua` is *INCOMPLETE*, me doing the [ByteBuddy](https://bytebuddy.net/) demo to create a new class with a new `toString()` at runtime.

`java/tests/bytebuddy_native.lua` is *INCOMPLETE*, me using ByteBuddy to create new Runnable implementation to do dynamic LuaJIT -> Java -> LuaJIT stuff without running `javac` or installing a Java SDK.

# TODO

- generics
- functions / lambdas
- I'm not building proper reflection for arrays I think ... I'm using getFields()/getMethods(), but then I still have to explicitly grab the default ctor or the toString(), so maybe I should use getDeclaredFields()/getDeclaredMethods() and then manaully search inheritence myself? But then should I be caching the class tree refs to parent myself too?
- call resolve score should consider subclass distances instead of just IsAssignableFrom.  See the note on caching the whole inheritence structure.
- I'm setting up the initial classes used for java, reflection, etc in JNIEnv's ctor ... I'm using my class system itself to setup my class system ... I should just replace this with direct JNI calls to make everything less error prone.
- some kind of Lua syntax sugar for easy nonvirtual calls ... right now you have to do something like `obj:_method{name=name, sig=sig, nonvirtual=true}(obj, ...)`
- maybe make a specific `java.thread` subclass centered around [`lua-thread`](http://github.com/thenumbernine/lua-thread)'s "thread.lite", but honesty it is slim enough that I don't see the reason why.
