import org.objectweb.asm.*;
public class TestClassVisitor extends ClassVisitor {
	public TestClassVisitor() {
		super(Opcodes.ASM9);
	}

	public void visit(
		int version,
		int access,
		String name,
		String signature,
        String superName,
		String[] interfaces
	) {
		System.out.println(
			"header "
			+version+", "
			+access+", "
			+name+", "
			+signature+", "
			+superName+", "
			+interfaces);
		if (interfaces != null) {
			for (String ifname : interfaces) {
				System.out.println("\t"+ifname);
			}
		}
	}

    public void visitSource(String source, String debug) {
		System.out.println("source "+source+", "+debug);
	}

    public void visitOuterClass(String owner, String name, String desc) {
		System.out.println("outerclass "+owner+", "+name+", "+desc);
	}

    public AnnotationVisitor visitAnnotation(String desc, boolean visible) {
		System.out.println("annotation "+desc+", "+visible);
		return super.visitAnnotation(desc, visible);
	}

    public void visitAttribute(Attribute attr) {
		System.out.println("attribute "+attr);
	}

    public void visitInnerClass(String name, String outerName, String innerName, int access) {
		System.out.println("innerclass "+name+", "+outerName+", "+innerName+", "+access);
	}

	public FieldVisitor visitField(
		int access,
		String name,
		String descriptor,
		String signature,
		Object value
	) {
		System.out.println(
			"field "
			+access+", "
			+name+", "
			+descriptor+", "
			+signature+", "
			+value);
		return super.visitField(access, name, descriptor, signature, value);
	}

    public MethodVisitor visitMethod(
		int access,
		String name,
		String desc,
        String signature,
		String[] exceptions
	) {
		System.out.println("method "+access+", "+name+", "+desc+", "+signature+", "+exceptions);
		if (exceptions != null) {
			for (String ex : exceptions) {
				System.out.println("\t"+ex);
			}
		}
		return super.visitMethod(access, name, desc, signature, exceptions);
	}

	public void visitEnd() {
		System.out.println("end");
	}
}
