# Java in LuaJIT

I'm sure this has been done before, but here's my version.

### JVM
`JVM = require 'java.vm'`

- `jvm = JVM(args)` = creates a new VM
- args:
- - `version` = specify which version, defaults to `JNI_VERSION_1_6`
- - `classpath` = specify an additional `-Djava.class.path=` option.

- - `jvm._ptr` = the `JavaVM*` pointer

- `jvm:destroy()` = clean up the VM

- `jvm.jniEnv` = a JNIEnv object

### JNIEnv
`JNIEnv = require 'java.jnienv'`

- `jniEnv = JNIEnv(ptr)` = create a JNIEnv object with the specified `JNIEnv*` pointer

- `jniEnv._ptr` = the `JNIEnv*` pointer

- `jniEnv._classesLoaded` = internal cache of loaded class-wrappers

- `jniEnv:_version()` = returns the JNIEnv version, usually a hex number.

- `jniEnv:_str(s)`
- - if `s` is a string, returns a JavaObject wrapping a `java.lang.String` of the Lua-string contents of `s` using C API `JNIEnv.NewStringUTF`.
- - if `s` is cdata, does the same but treating it as a memory pointer.
- `jniEnv:_str(s, len)`
- - if `s` is a string, converts it to a `jchar[]` array and uses C API `JNIEnv.NewString`
- - if `s` is cdata, treats it as-is using C API `JNIEnv.NewString`
- see `JavaString`

- `jniEnv:_newArray(javaType, length, objInit)`
- - creates a Java array using one of the C API `JNIEnv.New*Array` methods
- - see `JavaArray`

- `jclass = jniEnv:_getObjClass(objPtr)` = returns a `jclass` pointer for a `jobject` pointer.  Wrapper for C API `JNIEnv.GetObjectClass`.

- `classpath, jclass = jniEnv:_getObjClassPath(objPtr)` = returns a Lua string of the classpath and `jclass` for the object in `objPtr`.

- `classObj = jniEnv:_saveJClassForClassPath(args)` = always creates a new JavaClass object for the `jclass` pointer, and saves it in this env's `_classesLoaded` table for this `classpath`.

- `jniEnv:_class(classpath)` = look up a Java class using C API `JNIEnv.FindClass`.

- `ex = jniEnv:_exceptionOccurred()` = if an exception occurred then returns the exception JavaObject.

- `jniEnv:_checkExceptions()` = if an exception occurred, throw it as an error.

- `jniEnv:_luaToJavaArg(arg, sig)` = convert a Lua object `arg` to a JNI pointer object. Preparation for the JNI API.  `sig` is a Java type to help in conversion, namely when `arg` is a number.
- `jniEnv:_luaToJavaArgs(sigIndex, sig, ...)` = convert a vararg of Lua objects to JNI pointer objects.  `sig` is an array used for function signatures, `sigIndex` is the location in that array.

- `jniEnv:__index(k)` = if `jniEnv` is indexed with any other key then it is assumed to be a namespace lookup.
- - ex: `jniEnv.java` retrieves the namespace `java.*`
- - ex: `jniEnv.java.lang` retrieves the namespace `java.lang.*`
- - ex: `jniEnv.java.lang.String` retrieves the JavaClass `java.lang.String`
- - TODO still need to incorporate lookups for methods and members

### JavaClass
`JavaClass = require 'java.class'`

- `cl = JavaClass(args)` = `jclass` wrapper
- args:
- - `env` = the `JNIEnv` Lua object
- - `ptr` = the `jclass`
- - `classpath` = the classpath of this class

- `cl:_method(args)` = returns a `JavaMethod` object for a `jmethodID`.
- args:
- - `name` = the method name
- - `sig` = the method signature, a table of classpaths/primitives, the first is the return type.  An empty table defaults to a `void` return type.
- - `static` = set to `true` to retrieve a static method.

- `cl:_field(args)` = returns a `JavaField` object for a `jfieldID`.
- args:
- - `env` = `JNIEnv` object.
- - `ptr` = `jfieldID`.
- - `name` = field name.
- - `sig` = signature string of the field.
- - `static` = true for static fields.

- `cl:_name()` = returns the classpath of the object, using Java's `class.getName()` method, and then attempt to reverse-translate signature-encoded names, i.e. a `double[]` Java object would have a `class.getName()` of `[D`, but this would decode it back to `double[]`.

### JavaObject
`JavaObject = require 'java.object'`

- `obj = JavaObject(args)` = wrapper for a Java `jobject`
- args:
- - `env` = `JNIEnv`
- - `ptr` = `jobject`
- - `classpath` = string

- `cl = JavaObject._getLuaClassForClassPath(classpath)` = helper to get the Lua class for the Java classpath.

- `obj = JavaObject._createObjectForClassPath(classpath, args)` = helper to create the appropriate Lua wrapper object, with arguments, for the Java classpath.

- `cl = obj:_class()` = get class

- `method = obj:_method(args)` = shorthand for `obj:_class():method(args)`.

- `field = obj:_field(args)` = shorthand

- `str = obj:_javaToString()` = returns a Lua string based on the Java `toString()` method.

- `str = obj:_getDebugStr()` = useful internal string with a few things like the Lua class name, Java classpath, and pointer.

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
- - `static` = whether this method is static or not.

- `result = method(...)` = invoke ` call on the method using C API `JNIEnv.Call*Method`.

- `obj = method:_new(...)` = for constructor methods, calls C API `JNIEnv.NewObject` on this method.

### JavaString
`JavaString = require 'java.string'`

- `s = JavaString(args)` = inherited from JavaObject.

- `tostring(s)` aka `s:__tostring()` = returns the Java string contents.

- `#s` aka `s:__len()` = returns the Java string length.

### JavaArray
`JavaArray = require 'java.array'`

- `ar = JavaArray(args)` = inherited from JavaObject, and:
- args:
- - `elemClassPath` = classpath of the array element, needed for subequent operations.

- `ar.elemFFIType` = for primitives, LuaJIT FFI ctype of the JNI primitive type.
- `ar.elemFFIType_1` = for primitives, LuaJIT FFI ctype of a 1-length array of the JNI primitive type.
- `ar.elemFFIType_ptr` = for primitives, LuaJIT FFI ctype of a pointer of the JNI primitive type.

- `#ar` aka `ar:__len()` = return the length of the Java array.

- `ar[i]` aka `ar:_get(i)` = get the i'th index of the array
- `ar[i]=v` aka `ar:_set(i, v)` = set the i'th index of the array

<hr>

Also for JNI, JavaClass, and JavaObject (and subclasses JavaString and JavaArray),
the Lua `__index` and `__newindex` works for fields and methods.

Be sure to always use `obj:func(...)` when calling, even if it's calling a static method, even from a Java class, because Lua needs the context of it, be it objects or classes.

<hr>

I made this to go with my [SDL-LuaJIT](https://github.com/thenumbernine/SDLLuaJIT-android) launcher.

The `java.ffi.jni` file is [`lua-include`](https://github.com/thenumbernine/include-lua) run on `jni.h`.

# TODO

- `jni:_new(obj, args...)`, `class:_new(args)` to auto grab the ctor method ... needs runtime name resolution
- proper symbol overload resolution based on method # of args and coercion or whatever
