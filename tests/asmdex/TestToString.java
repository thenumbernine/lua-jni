// trying to java implement my auto gen lua class wrapper functions
public class TestToString {
	public String toString() {
		return (String)io.github.thenumbernine.NativeCallback.run(
			0xdeadbeefcafebebeL,
			new Object[]{this}
		);
	}

	public double testFwdArgs(int a, long b, Object c, double d, float e) {
		Double res = (Double)io.github.thenumbernine.NativeCallback.run(
			0xdeadbeefcafebebeL,
			new Object[]{
				this,
				Integer.valueOf(a),
				Long.valueOf(b),
				c,
				Double.valueOf(d),
				Float.valueOf(e)
			}
		);
		return res.doubleValue();
	}
}

/*
{
	fields={},
	isPublic=true,
	methods={
		{
			code={
				{"invoke-direct", "Ljava/lang/Object;", "<init>", "()V", "v0"},
				{"return-void", 0}
			},
			codeData={112, 16, 9, 0, 0, 0, 14, 0},
			isConstructor=true,
			isPublic=true,
			maxRegs=1,
			name="<init>",
			regsIn=1,
			regsOut=1,
			sig={"void"}
		},
		{
# init regs: [v0=this, v1=a, v2&v3=b, v4=c, v5&v6=d, v7=e]
			code={
{"nop", 0},

# Integer v1 = Integer.valueOf(v1 = int a)
{"invoke-static", "Ljava/lang/Integer;", "valueOf", "(I)Ljava/lang/Integer;", "v1"},
{"move-result-object", "v1"},

# Long v2 = Long.valueOf(v2&v3l = long b)
{"invoke-static", "Ljava/lang/Long;", "valueOf", "(J)Ljava/lang/Long;", "v2", "v3"},
{"move-result-object", "v2"},

# Double v3 = Double.valueOf(v5&v6 = double d)
{"invoke-static", "Ljava/lang/Double;", "valueOf", "(D)Ljava/lang/Double;", "v5", "v6"},
{"move-result-object", "v3"},

# Float v5 = Float.valueOf(v7 = float e)
{"invoke-static", "Ljava/lang/Float;", "valueOf", "(F)Ljava/lang/Float;", "v7"},
{"move-result-object", "v5"},

# v6 = 6
{"const/4", "v6", 6},
# v6 = args = new Object[6]
{"new-array", "v6", "v6", "[Ljava/lang/Object;"},

# v7 = 0
{"const/4", "v7", 0},
# v6[v7] = v0, i.e. args[0] = this
{"aput-object", "v0", "v6", "v7"},

# v7 = 1
{"const/4", "v7", 1},
# v6[v7] = v1, i.e. args[1] = Integer.valueOf(a)
{"aput-object", "v1", "v6", "v7"},

# v1 = 2
{"const/4", "v1", 2},
# v6[v1] = v2, i.e. args[2] = Long.valueOf(b)
{"aput-object", "v2", "v6", "v1"},

# v1 = 3
{"const/4", "v1", 3},
# v6[v1] = v4, i.e. args[3] = c
{"aput-object", "v4", "v6", "v1"},

# v1 = 4
{"const/4", "v1", 4},
# v6[v1] = v3 i.e. args[4] = Double.valueOf(d)
{"aput-object", "v3", "v6", "v1"},

# v1 = 5
{"const/4", "v1", 5},
# v6[v1] = v5, i.e. args[5] = Float.valueOf(e)
{"aput-object", "v5", "v6", "v1"},

# v1&v2 = funcptr
{"const-wide", "v1", [cdata:-2401053089206452546LL]},

# result = res = run(v1, v2, v6), i.e. run(funcptr, args);
{"invoke-static", "Lio/github/thenumbernine/NativeCallback;", "run", "(JLjava/lang/Object;)Ljava/lang/Object;", "v1", "v2", "v6"},

# v1 = result
{"move-result-object", "v1"},

# v1 = (Double)result
{"check-cast", "v1", "Ljava/lang/Double;"},

# result2 = ((Double)result).doubleValue()
{"invoke-virtual", "Ljava/lang/Double;", "doubleValue", "()D", "v1"},

# v1&v2 = result2
{"move-result-wide", "v1"},

# return v1&v2
# 		.... why not return 0?  because 'this' needs to go out as well?
{"return-wide", "v1"}
			},
			codeData={
0, 0,
113, 16, 7, 0, 1, 0,
12, 1,
113, 32, 8, 0, 50, 0,
12, 2,
113, 32, 5, 0, 101, 0,
12, 3,
113, 16, 6, 0, 7, 0,
12, 5,
18, 102,
35, 102, 13, 0,
18, 7,
77, 0, 6, 7,
18, 23,
77, 1, 6, 7,
18, 33,
77, 2, 6, 1,
18, 49,
77, 4, 6, 1,
18, 65,
77, 3, 6, 1,
18, 81,
77, 5, 6, 1,
24, 1, 190, 190, 254, 202, 239, 190, 173, 222,
113, 48, 3, 0, 33, 6,
12, 1,
31, 1, 6, 0,
110, 16, 4, 0, 1, 0,
11, 1,
16, 1},
			isPublic=true,
			maxRegs=8,
			name="testFwdArgs",
			regsIn=8,
			regsOut=3,
			sig={"double", "int", "long", "java.lang.Object", "double", "float"}
		},
		{
# init regs: [v0=?, v1=?, v2=?, v3=this]
			code={
# v0 = 1
{"const/4", "v0", 1},
# args = v0 = new Object[1]
{"new-array", "v0", "v0", "[Ljava/lang/Object;"},
# v1 = 0
{"const/4", "v1", 0},
# v0[v1] = this i.e. args[0] = this
{"aput-object", "v3", "v0", "v1"},
# v1,v2 = funcptr
{"const-wide", "v1", [cdata:-2401053089206452546LL]},
# res = NativeCallback.run(v1,v2, v0), i.e. (funcptr, args);
{"invoke-static", "Lio/github/thenumbernine/NativeCallback;", "run", "(JLjava/lang/Object;)Ljava/lang/Object;", "v1", "v2", "v0"},
# v0 = res
{"move-result-object", "v0"},
# v0 = (String)res
{"check-cast", "v0", "Ljava/lang/String;"},
# return res
{"return-object", "v0"}
			},
			codeData={
18, 16,
35, 0, 13, 0,
18, 1,
77, 3, 0, 1,
24, 1, 190, 190, 254, 202, 239, 190, 173, 222,
113, 48, 3, 0, 33, 0,
12, 0,
31, 0, 11, 0,
17, 0
},
			isPublic=true,
			maxRegs=4,
			name="toString",
			regsIn=1,
			regsOut=3,
			sig={"java.lang.String"}
		}
	},
	sourceFile="TestToString.java",
	superClass="java.lang.Object",
	thisClass="TestToString",
}
*/
